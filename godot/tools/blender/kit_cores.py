"""Ядра кита: origin = центр; якоря — кадры HUMAN_ANCHORS (контракт позы: плечи/бёдра −Y вниз, бока ±60°, шея вверх).
Позиции якорей у ядер свои, но в коридоре контракта: плечи x ±0.19…0.26, y +0.20…+0.30; бёдра x ±0.08…0.14, y −0.22…−0.30;
шея y +0.26…+0.32. Под каждым плечом и бедром — видимая бобышка/кронштейн, шар шарнира на якоре садится на неё."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


def _rot(name):
    """Поворот якоря ядра — как в HUMAN_ANCHORS (контракт позы одинаков у всех ядер)."""
    return {n: r for n, _p, r in HUMAN_ANCHORS}[name]


def _anchors(pos):
    """Якоря ядра: позиции свои (pos: имя → (x, y, z); правая сторона — зеркало левой), кадры — HUMAN_ANCHORS."""
    out = []
    for n, p, r in HUMAN_ANCHORS:
        if n in pos:
            p = pos[n]
        elif n.endswith("_R") and n[:-2] + "_L" in pos:
            q = pos[n[:-2] + "_L"]
            p = (-q[0], q[1], q[2])
        out.append(anchor(n, p, r))
    return out


def _boss(prefix, pos, d, r, h, mat="Iron", bolts=0, segs=16):
    """Бобышка вдоль d: низ утоплен в корпус на 0.02, торец с фаской на высоте h; bolts — шестигранные болты по кругу торца."""
    d = Vector(d).normalized()
    prof = [(0.0, -0.02), (r, -0.02), (r, h * 0.7), (r * 0.88, h), (0.0, h)]
    objs = [fin(revolve(prefix, prof, mat, segs, align_y(d, pos)), 0.0, angle=50.0, uv="cyl")]
    if bolts:
        side = d.cross(Vector((0.0, 0.0, 1.0)) if abs(d.z) < 0.9 else Vector((1.0, 0.0, 0.0))).normalized()
        up = d.cross(side).normalized()
        for k in range(bolts):
            a = TAU * k / bolts + math.pi / bolts
            p = Vector(pos) + d * (h * 0.96) + (side * math.cos(a) + up * math.sin(a)) * r * 0.66
            objs.append(fin(stud(prefix + "Bolt", p, d, "Steel", r * 0.13, r * 0.09, 6)))
    return objs


def _cup(prefix, pos, d, r, depth=0.03, segs=16):
    """Круглое гнездо-чашка (как на белом ядре листа автора): железное кольцо с губой, внутри впадина под шар шарнира."""
    prof = [(0.0, -depth), (r * 0.95, -depth), (r, -0.004), (r * 1.1, 0.006), (r * 1.06, 0.018), (r * 0.84, 0.021),
            (r * 0.74, 0.008), (r * 0.7, -0.002), (0.0, -0.004)]
    return [fin(revolve(prefix, prof, "Iron", segs, align_y(d, pos)), 0.0, angle=50.0)]


def _flange(prefix, cy, z_back, z_front, r, bolts=8, segs=28):
    """Круглый фланец под окошко Ядра на выпуклом корпусе (лаз котла): торец плоский — кольцо и заклёпки окошка ложатся на него."""
    h = z_front - z_back
    prof = [(0.0, 0.0), (r, 0.0), (r, h - 0.006), (r - 0.006, h), (0.0, h)]
    objs = [fin(revolve(prefix, prof, "Iron", segs, align_y((0, 0, 1), (0.0, cy, z_back))), 0.0, angle=50.0, uv="box")]
    for k in range(bolts):
        a = TAU * k / bolts + math.pi / bolts
        objs.append(fin(stud(prefix + "Bolt", (math.cos(a) * (r - 0.011), cy + math.sin(a) * (r - 0.011), z_front - 0.001),
                             (0, 0, 1), "Steel", 0.0065, 0.0045, 6)))
    return objs


def _seam(prefix, y, r, h, mat, segs=28):
    """Пояс-накладка вокруг оси Y (как kit_common.band, без фаски — дешевле по треугольникам)."""
    return fin(revolve(prefix, [(r * 0.985, y + h / 2), (r, y + h * 0.3), (r, y - h * 0.3), (r * 0.985, y - h / 2)], mat, segs,
                       closed=True), 0.0, angle=50.0, uv="cyl")


def _player_band(prefix, y_top, y_bot, rad, lift=0.003, segs=28, steps=2, sink=0.004):
    """Широкий пояс цвета игрока (Shirt_Kit) на теле вращения: наружная сторона — rad(y) + lift от y_top до y_bot (steps
    промежутков повторяют изгиб корпуса), кромки скруглены к корпусу, внутренняя сторона утоплена в него на sink.
    Зачем (29.09, QA на Свалке): на игровом расстоянии (полувысота кадра ~4 м) шары шарниров и тонкие полоски — несколько
    пикселей, и кукла читалась цветом своей краски, а не цветом игрока. У каждого ядра площадь цвета игрока — ≥ ~15 %
    фронтального силуэта (BODY_KIT.md §1, «Цвет игрока на ядре»)."""
    e = min(0.004, (y_top - y_bot) * 0.1)
    prof = [(rad(y_top) - sink, y_top), (rad(y_top - e) + lift * 0.55, y_top - e * 0.25)]
    for i in range(steps + 1):
        y = y_top - e - (y_top - y_bot - 2.0 * e) * i / steps
        prof.append((rad(y) + lift, y))
    prof += [(rad(y_bot + e) + lift * 0.55, y_bot + e * 0.25), (rad(y_bot) - sink, y_bot)]
    return fin(revolve(prefix, prof, "Shirt_Kit", segs, closed=True), 0.0, angle=50.0, uv="cyl")


def _ribbon(name, pts, nrms, width, mat, lift=0.003, sink=0.004):
    """Лента по поверхности (помочи, ремень): точки pts на корпусе, нормали nrms; сечение — прямоугольник width × (lift + sink),
    наружу на lift, внутрь корпуса на sink. Лофт прямоугольных сечений с торцами."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector(nrms[i]).normalized()
        s = t.cross(n).normalized() * (width * 0.5)
        rings.append([p + s + n * lift, p - s + n * lift, p - s - n * sink, p + s - n * sink])
    return fin(loft(name, rings, mat), 0.0, angle=50.0)


def _ry(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Y')


def _prof_r(prof, y):
    """Радиус тела вращения на высоте y (профиль [(r, y)] сверху вниз, линейная интерполяция)."""
    for (r0, y0), (r1, y1) in zip(prof, prof[1:]):
        if y1 <= y <= y0 and y0 > y1:
            return r0 + (r1 - r0) * (y0 - y) / (y0 - y1)
    return prof[-1][0]


def build_Core_Barrel(base="Wood"):
    """Ядро-бочка: 16 клёпок-досок с пазами, железные обручи, широкий обруч цвета игрока под окошком Ядра, крышка,
    кронштейны плеч, окошко Ядра."""
    y0, y1, r_end, r_mid = 0.275, -0.255, 0.168, 0.2

    def rad(y):
        t = (y0 - y) / (y0 - y1)
        return r_end + (r_mid - r_end) * math.sin(math.pi * t)

    objs = []
    staves = 16
    for s in range(staves):
        a0 = TAU * s / staves + 0.012
        a1 = TAU * (s + 1) / staves - 0.012
        rings = []
        for k in range(9):
            y = y0 + (y1 - y0) * k / 8
            r = rad(y)
            ri = r - 0.022
            ring = [(r * math.sin(a), y, r * math.cos(a)) for a in (a0, (a0 + a1) / 2, a1)]
            ring += [(ri * math.sin(a), y, ri * math.cos(a)) for a in (a1, (a0 + a1) / 2, a0)]
            rings.append(ring)
        objs.append(fin(loft("CB_Stave", rings, "Base_" + base), angle=35.0, uv="box"))
    objs.append(fin(revolve("CB_Inner", [(0.0, y0 - 0.02), (r_end - 0.015, y0 - 0.02), (r_mid - 0.018, 0.0), (r_end - 0.015, y1 + 0.02),
                                        (0.0, y1 + 0.02)], "WoodDark", 20), uv="cyl"))
    for y in (0.235, 0.17, -0.215):
        objs.append(band("CB_Hoop", y, rad(y) + 0.006, 0.026, "Iron"))
        objs += ring_rivets("CB_HoopRivet", y, rad(y) + 0.008, 8, "Steel", 0.0055, front_only=True, phase=0.2)
    # обруч цвета игрока вместо третьего железного (−0.15): под окошком Ядра, до нижнего обруча
    objs.append(_player_band("CB_PlayerBand", -0.05, -0.17, rad, lift=0.005, segs=24))
    objs.append(fin(revolve("CB_Lid", [(0.0, y0 - 0.012), (r_end - 0.012, y0 - 0.012), (r_end - 0.012, y0 - 0.002), (0.0, y0 - 0.002)],
                            "WoodDark", 24), uv="box"))
    for sx in (-1, 1):
        objs.append(rbox("CB_ShoulderBracket", (0.075, 0.05, 0.08), "Iron", (sx * 0.19, 0.255, 0.0), 0.012, 2))
        objs.append(fin(stud("CB_BracketBolt", (sx * 0.19, 0.255, 0.041), (0, 0, 1), "Steel", 0.009, 0.006, 6)))
        objs.append(rbox("CB_SidePlate", (0.03, 0.08, 0.08), "Iron", (sx * 0.2, 0.0, 0.0), 0.01, 2))
        objs.append(rbox("CB_HipBracket", (0.06, 0.05, 0.08), "Iron", (sx * 0.1, -0.25, 0.0), 0.012, 2))
    objs += porthole("CB_Core", (0.0, 0.035, 0.205))
    empties = [anchor(n, p, r) for n, p, r in HUMAN_ANCHORS] + [shape_box("Torso", (0.0, 0.0, 0.0), (0.36, 0.52, 0.22))]
    return objs, empties


def build_Core_Crate(base="Planks"):
    """Ядро-ящик: доски с пазами, железные уголки, кронштейны плеч и бёдер, накладки боков, фланец шеи, полоса цвета игрока,
    окошко Ядра. Пазы режут
    ящик насквозь — внутри вкладыш из ореха на 6 мм глубже граней: дно пазов, сквозь щели между досками не видно фона."""
    shell = box("CC_Shell", (0.40, 0.50, 0.30), "Base_" + base, (0.0, 0.0, 0.0))
    for y in (-0.125, 0.0, 0.125):
        cut_box(shell, (0.0, y, 0.0), (0.5, 0.008, 0.5))
    objs = [fin(shell, 0.012, 2, angle=40.0)]
    objs.append(fin(box("CC_Filler", (0.388, 0.488, 0.288), "WoodDark", (0.0, 0.0, 0.0))))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = Vector((sx * 0.19, sy * 0.24, sz * 0.14))
                objs.append(rbox("CC_Corner", (0.05, 0.05, 0.05), "Iron", p, 0.01, 2))
                objs.append(fin(stud("CC_Nail", p + Vector((0, 0, sz * 0.026)), (0, 0, sz), "Steel", 0.007, 0.004, 6)))
        objs.append(rbox("CC_HipBracket", (0.06, 0.04, 0.08), "Iron", (sx * 0.1, -0.255, 0.0), 0.01, 2))
        # кронштейн плеча — на кромке крышки под шаром сустава (как у бочки); накладка бока — под Side
        objs.append(rbox("CC_ShoulderBracket", (0.07, 0.045, 0.08), "Iron", (sx * 0.192, 0.254, 0.0), 0.011, 2))
        objs.append(fin(stud("CC_BracketBolt", (sx * 0.192, 0.254, 0.041), (0, 0, 1), "Steel", 0.008, 0.005, 6)))
        objs.append(rbox("CC_SidePlate", (0.022, 0.09, 0.09), "Iron", (sx * 0.203, 0.0, 0.0), 0.007, 2))
        for sy in (-1, 1):
            objs.append(fin(stud("CC_SideNail", (sx * 0.214, sy * 0.03, 0.03), (sx, 0, 0), "Steel", 0.006, 0.004, 6)))
    objs += _boss("CC_Neck", (0.0, 0.25, 0.0), (0, 1, 0), 0.052, 0.026, bolts=4)
    objs.append(fin(sweep("CC_Strap", [(-0.205, 0.07, 0.155), (0.205, 0.07, 0.155)], 0.012, "Iron", sides=4), angle=40))
    # полоса цвета игрока вокруг ящика: под окошком Ядра, между пазом −0.125 и нижними уголками (_player_band — у тел вращения)
    objs.append(rbox("CC_PlayerBand", (0.41, 0.086, 0.31), "Shirt_Kit", (0.0, -0.173, 0.0), 0.004, 1))
    objs += porthole("CC_Core", (0.0, -0.04, 0.155))
    empties = [anchor(n, p, r) for n, p, r in HUMAN_ANCHORS] + [shape_box("Torso", (0.0, 0.0, 0.0), (0.40, 0.50, 0.30))]
    return objs, empties


def build_Core_Ball(base="PaintRed"):
    """Ядро-хаб (как «CORES» на листе автора): шар с гнёздами-бобышками на каждом якоре, обод с заклёпками, пояс цвета
    игрока под ободом (между бобышками боков и бёдер), окошко Ядра."""
    R = 0.2
    objs = [fin(sphere("CO_Ball", R, (0, 0, 0), "Base_" + base, 32, 16), angle=60.0, uv="cyl")]
    objs.append(fin(torus("CO_Equator", (0, 0, 0), R + 0.004, 0.012, "Iron", 'XZ', 32, 6), angle=80))
    objs += ring_rivets("CO_Rivet", 0.0, R + 0.012, 12, "Steel", 0.007, front_only=True)
    objs.append(_player_band("CO_PlayerBand", -0.066, -0.153, lambda y: math.sqrt(max(R * R - y * y, 0.0)), lift=0.004, segs=32,
                             steps=3))
    # (имя, угол бобышки в плоскости XY, расстояние якоря от центра): плечи на 46° — в коридоре контракта (x 0.19+, y 0.20+)
    anchors = [("Neck", 90.0, 0.262), ("Shoulder_L", 46.4, 0.283), ("Shoulder_R", 133.6, 0.283), ("Side_L", -5.0, 0.262),
               ("Side_R", 185.0, 0.262), ("Hip_L", -62.0, 0.262), ("Hip_R", -118.0, 0.262)]
    empties = []
    for nm, deg, dist in anchors:
        d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))
        h = 0.045 + (dist - 0.262)      # плечи дальше — бобышка выше, шар сустава всё так же садится на торец
        objs.append(fin(revolve("CO_Boss", [(0.0, 0.0), (0.056, 0.0), (0.056, h - 0.015), (0.05, h), (0.0, h)], "Iron", 20,
                                align_y(d, d * (R - 0.012))), 0.004, 1, uv="cyl"))
        for k in range(5):
            a = TAU * k / 5
            side = d.cross(Vector((0, 0, 1)))
            p = d * (R + h - 0.011) + (side * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)) * 0.057
            objs.append(fin(stud("CO_BossBolt", p, side * math.cos(a) + Vector((0, 0, 1)) * math.sin(a), "Steel", 0.006, 0.004, 6)))
        # кадр якоря — как у всех ядер (контракт позы): плечи/бёдра −Y вниз, бока ±60°, шея вверх; бобышка смотрит по d
        empties.append(anchor(nm, tuple(d * dist), _rot(nm)))
    objs += porthole("CO_Core", (0.0, 0.0, 0.2), 0.07)
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


def build_Core_Boiler(base="RustRed"):
    """Ядро-котёл: клёпаный крашеный лист, купол с горловиной шеи, латунный манометр, короткая труба, лаз с окошком Ядра,
    два пояса цвета игрока (над лазом и под ним)."""
    prof = [(0.0, 0.27), (0.045, 0.268), (0.085, 0.259), (0.118, 0.244), (0.144, 0.224), (0.161, 0.2), (0.169, 0.18), (0.17, 0.165),
            (0.17, -0.2), (0.0, -0.2)]
    R = 0.17
    objs = [fin(revolve("CBo_Shell", prof, "Base_" + base, 32), 0.0, angle=50.0, uv="cyl")]
    # топка-юбка (на ней бёдра) и швы внахлёст с заклёпками
    objs.append(fin(revolve("CBo_Skirt", [(0.0, -0.19), (0.172, -0.19), (0.177, -0.2), (0.182, -0.244), (0.188, -0.252),
                                          (0.188, -0.262), (0.0, -0.262)], "Iron", 28), 0.0, angle=50.0, uv="cyl"))
    objs.append(_seam("CBo_Seam", 0.165, R + 0.003, 0.022, "RustDark"))
    objs += ring_rivets("CBo_SeamRivet", 0.165, R + 0.005, 16, "Steel", 0.0055, front_only=True, phase=0.08)
    objs += ring_rivets("CBo_SkirtRivet", -0.225, 0.183, 10, "Steel", 0.006, front_only=True)
    # вертикальный шов: накладка и столбик заклёпок (сбоку, чтобы не спорить с окошком)
    a = 42.0
    objs.append(fin(box("CBo_Strap", (0.03, 0.282, 0.008), "RustDark", (0.0, 0.015, R + 0.002), _ry(a)), 0.002, 1))
    n = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
    for i in range(6):
        objs.append(fin(stud("CBo_StrapRivet", n * (R + 0.006) + Vector((0.0, -0.095 + 0.046 * i + 0.01, 0.0)), n, "Steel", 0.0055,
                             0.004, 6)))
    # два пояса цвета игрока: над лазом (под верхним швом) и под ним (вместо нижнего шва, до топки-юбки)
    objs.append(_player_band("CBo_PlayerBand", 0.152, 0.088, lambda y: R, lift=0.003, segs=32))
    objs.append(_player_band("CBo_PlayerBandLow", -0.128, -0.186, lambda y: R, lift=0.003, segs=28))
    # лаз: фланец с болтами, в нём окошко Ядра
    objs += _flange("CBo_Hatch", -0.02, 0.12, 0.178, 0.1, bolts=8)
    objs += porthole("CBo_Core", (0.0, -0.02, 0.183), 0.06)
    # горловина шеи на куполе
    objs += _boss("CBo_Neck", (0.0, 0.262, 0.0), (0, 1, 0), 0.058, 0.03)
    # латунный манометр на куполе спереди (слева на экране): патрубок, корпус, шкала, стрелка
    sp = Vector((-0.075, 0.214, 0.0))
    sp.z = math.sqrt(max(_prof_r(prof, sp.y) ** 2 - sp.x ** 2, 0.0))
    d = Vector((-0.28, 0.2, 1.0)).normalized()
    c = sp + Vector((0.0, 0.012, 0.042))
    objs.append(fin(sweep("CBo_GaugePipe", [sp - Vector((0, 0, 0.01)), sp + Vector((0.0, 0.006, 0.02)), c - d * 0.01], 0.008, "Brass",
                          sides=8), angle=60))
    objs.append(fin(revolve("CBo_Gauge", [(0.0, -0.012), (0.04, -0.012), (0.043, -0.004), (0.043, 0.008), (0.038, 0.014),
                                          (0.033, 0.01), (0.0, 0.01)], "Brass", 24, align_y(d, c)), 0.0, angle=50.0))
    objs.append(fin(revolve("CBo_Dial", [(0.0, 0.0), (0.033, 0.0), (0.033, 0.003), (0.0, 0.003)], "Bone", 24, align_y(d, c + d * 0.009)),
                    angle=60))
    up = (Vector((0, 1, 0)) - d * d.y).normalized()
    rt = up.cross(d).normalized()
    tip = c + d * 0.014 + (up * math.cos(0.7) + rt * math.sin(0.7)) * 0.026
    objs.append(fin(sweep("CBo_Needle", [c + d * 0.014, tip], [0.0035, 0.0015], "RustDark", sides=4), angle=60))
    objs.append(fin(stud("CBo_NeedlePin", c + d * 0.0135, d, "Brass", 0.005, 0.004, 6)))
    # короткая дымовая труба сзади (справа на экране, где её видно из-за плеча), фланец и раструб
    b = Vector((0.078, 0.244, -0.078))
    pipe = [b, b + Vector((0.016, 0.056, -0.016)), b + Vector((0.04, 0.101, -0.04))]
    objs.append(fin(sweep("CBo_Stack", pipe, 0.024, "Iron", sides=12), angle=50, uv="cyl"))
    objs.append(fin(revolve("CBo_StackBase", [(0.0, -0.012), (0.038, -0.012), (0.038, 0.006), (0.03, 0.014), (0.0, 0.014)], "Iron", 14,
                            align_y((0.25, 1.0, -0.25), b)), 0.0, angle=50.0))
    tipd = (pipe[2] - pipe[1]).normalized()
    objs.append(fin(revolve("CBo_StackCap", [(0.0, -0.012), (0.027, -0.012), (0.036, 0.004), (0.034, 0.012), (0.02, 0.012),
                                             (0.018, 0.0), (0.0, 0.0)], "RustDark", 16, align_y(tipd, pipe[2])), 0.0, angle=50))
    # плечи — цапфы из купола с фланцем под шаром; бока — бобышки; бёдра — бобышки под юбкой
    for sx in (-1, 1):
        objs.append(fin(revolve("CBo_Trunnion", [(0.0, 0.0), (0.028, 0.0), (0.028, 0.07), (0.052, 0.074), (0.052, 0.09), (0.044, 0.097),
                                                 (0.0, 0.097)], "Iron", 16, align_y((sx, 0, 0), (sx * 0.112, 0.236, 0.0))),
                        0.0, angle=50.0, uv="cyl", axis='X'))
        objs += _boss("CBo_Side", (sx * 0.162, -0.02, 0.0), (sx, 0, 0), 0.042, 0.03)
        objs += _boss("CBo_Hip", (sx * 0.1, -0.258, 0.0), (0, -1, 0), 0.046, 0.018, segs=12)
    pos = {"Neck": (0.0, 0.305, 0.0), "Shoulder_L": (0.232, 0.236, 0.0), "Hip_L": (0.1, -0.285, 0.0), "Side_L": (0.205, -0.02, 0.0),
           "Back": (0.0, 0.2, -0.162)}
    return objs, _anchors(pos) + [shape_cyl("Torso", (0.0, 0.0, 0.0), 0.175, 0.53)]


def _toy_table():
    """Сечения корпуса «игрушки» сверху вниз: (y, полуширина x, полутолщина z, вынос центра по z) — грудь, перехват талии,
    живот (чуть вперёд), перехват под пояс, таз; одно гладкое тело."""
    return [(0.262, 0.075, 0.058, 0.0), (0.254, 0.13, 0.092, 0.0), (0.24, 0.168, 0.112, 0.0), (0.218, 0.19, 0.124, 0.002),
            (0.185, 0.2, 0.13, 0.004), (0.14, 0.198, 0.132, 0.006), (0.095, 0.186, 0.13, 0.006), (0.062, 0.166, 0.122, 0.005),
            (0.04, 0.151, 0.114, 0.003), (0.022, 0.137, 0.105, 0.002), (0.0, 0.133, 0.102, 0.003), (-0.022, 0.136, 0.107, 0.007),
            (-0.055, 0.144, 0.116, 0.011), (-0.09, 0.147, 0.117, 0.011), (-0.115, 0.143, 0.111, 0.008), (-0.13, 0.139, 0.105, 0.004),
            (-0.142, 0.142, 0.106, 0.0), (-0.162, 0.153, 0.11, -0.002), (-0.192, 0.16, 0.112, -0.003), (-0.222, 0.153, 0.106, -0.003),
            (-0.244, 0.132, 0.092, -0.002), (-0.258, 0.095, 0.068, 0.0), (-0.266, 0.045, 0.032, 0.0)]


def _toy_hw(y):
    """(полуширина, полутолщина, вынос по z) корпуса «игрушки» на высоте y."""
    tb = _toy_table()
    if y >= tb[0][0]:
        return tb[0][1:]
    for a, b in zip(tb, tb[1:]):
        if b[0] <= y <= a[0]:
            t = (a[0] - y) / (a[0] - b[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
    return tb[-1][1:]


def _toy_surface(p, d, e):
    """Точка на корпусе «игрушки» по лучу из p против d (шаг 2 мм): куда сажать гнездо под якорь."""
    d = Vector(d).normalized()
    q = Vector(p)
    for _i in range(200):
        hx, hz, zc = _toy_hw(q.y)
        if -0.272 < q.y < 0.268 and (abs(q.x) / hx) ** e + (abs(q.z - zc) / hz) ** e <= 1.0:
            return q
        q = q - d * 0.002
    return q


def build_Core_Toy(base="PaintWhite"):
    """Ядро-игрушка (белое ядро с листа автора): грудь, талия, живот и таз одним гладким крашеным телом, круглые
    гнёзда-чашки на каждом якоре, окошко Ядра в медальоне на груди, пояс и помочи цвета игрока, заводной ключ на спине."""
    e = 2.5
    rings = [[(x, y, z + zc) for x, z in superellipse(0.0, 0.0, hx, hz, 32, e)] for y, hx, hz, zc in _toy_table()]
    objs = [fin(loft("CT_Body", rings, "Base_" + base, pole0=(0.0, 0.268, 0.0), pole1=(0.0, -0.272, 0.0)), angle=75.0, uv="cyl")]
    # цвет игрока (BODY_KIT.md §1, «Цвет игрока на ядре»): широкий пояс в перехвате живот/таз и помочи от пояса через грудь
    # на плечи (по бокам медальона) — игрушечный комбинезон
    rings = []
    for y, d in ((-0.1, -0.004), (-0.103, 0.003), (-0.112, 0.005), (-0.134, 0.005), (-0.156, 0.005), (-0.165, 0.003), (-0.168, -0.004)):
        hx, hz, zc = _toy_hw(y)
        rings.append([(x, y, z + zc) for x, z in superellipse(0.0, 0.0, hx + d, hz + d, 32, e)])
    objs.append(fin(loft("CT_Belt", rings, "Shirt_Kit", caps=False), angle=50.0, uv="cyl"))

    def front(x, y):
        """Точка передней поверхности корпуса и нормаль (конечные разности)."""
        def z_at(xx, yy):
            hx, hz, zc = _toy_hw(yy)
            return zc + hz * max(1.0 - (abs(xx) / hx) ** e, 0.0) ** (1.0 / e)
        h = 0.002
        z = z_at(x, y)
        n = Vector((-(z_at(x + h, y) - z_at(x - h, y)) / (2 * h), -(z_at(x, y + h) - z_at(x, y - h)) / (2 * h), 1.0))
        return Vector((x, y, z)), n.normalized()

    for sx in (-1, 1):
        pts, nrms = [], []
        for k in range(9):
            y = -0.112 + (0.246 + 0.112) * k / 8
            x = sx * (0.112 + 0.012 * max(0.0, (y - 0.15) / 0.1))   # к плечу помоча чуть расходится
            p, n = front(x, y)
            pts.append(p)
            nrms.append(n)
        objs.append(_ribbon("CT_Strap", pts, nrms, 0.036, "Shirt_Kit", lift=0.004))
    # гнёзда: якорь = центр шара шарнира; чашка — на поверхности по лучу к якорю
    pos = {"Neck": (0.0, 0.302, 0.0), "Shoulder_L": (0.222, 0.228, 0.0), "Hip_L": (0.1, -0.288, 0.0), "Side_L": (0.186, -0.012, 0.0)}
    dirs = {"Neck": (0, 1, 0), "Shoulder_L": (1.0, 0.42, 0.0), "Hip_L": (0.2, -1.0, 0.0), "Side_L": (1.0, -0.3, 0.0)}
    size = {"Neck": 0.046, "Shoulder_L": 0.052, "Hip_L": 0.06, "Side_L": 0.048}
    for nm in pos:
        for sx in ((1, -1) if nm.endswith("_L") else (1,)):
            p = Vector((sx * pos[nm][0], pos[nm][1], pos[nm][2]))
            d = Vector((sx * dirs[nm][0], dirs[nm][1], dirs[nm][2])).normalized()
            objs += _cup("CT_Socket", _toy_surface(p, d, e) + d * 0.004, d, size[nm], segs=16)
    # гнездо спины (декор)
    _hx, hz, zc = _toy_hw(0.2)
    back_z = zc - hz
    objs += _cup("CT_BackSocket", (0.0, 0.2, back_z + 0.004), (0, 0, -1), 0.036, depth=0.025, segs=16)
    # медальон на груди (та же краска, литой) — плоский торец под окошко Ядра
    _hx, hz, zc = _toy_hw(0.125)
    zf = zc + hz + 0.003
    objs.append(fin(revolve("CT_Medallion", [(0.0, 0.0), (0.082, 0.0), (0.082, zf - 0.1 - 0.009), (0.078, zf - 0.1 - 0.002),
                                             (0.07, zf - 0.1), (0.0, zf - 0.1)], "Base_" + base, 28, align_y((0, 0, 1), (0.0, 0.125, 0.1))),
                    0.0, angle=45.0, uv="box"))
    objs += porthole("CT_Core", (0.0, 0.125, zf + 0.005), 0.056)
    # заводной ключ на спине (игрушка), латунь
    _hx, hz, zc = _toy_hw(-0.06)
    kz = zc - hz
    objs.append(fin(revolve("CT_KeyShaft", [(0.0, -0.01), (0.011, -0.01), (0.011, 0.045), (0.0, 0.045)], "Brass", 10,
                            align_y((0, 0, -1), (0.0, -0.06, kz + 0.006))), 0.0, angle=50))
    objs.append(fin(revolve("CT_KeyCollar", [(0.0, -0.006), (0.022, -0.006), (0.024, 0.004), (0.016, 0.01), (0.0, 0.01)], "Brass", 14,
                            align_y((0, 0, -1), (0.0, -0.06, kz + 0.002))), 0.0, angle=50))
    bow = []
    for i in range(24):
        a = TAU * i / 24
        bow.append((0.052 * math.cos(a), -0.06 + 0.034 * math.sin(a) * (0.42 + 0.58 * abs(math.cos(a)))))
    objs.append(fin(extrude2d("CT_KeyBow", bow, kz - 0.066, kz - 0.052, "Brass"), 0.003, 1))
    pos["Back"] = (0.0, 0.2, back_z - 0.014)
    return objs, _anchors(pos) + [shape_box("Torso", (0.0, -0.002, 0.0), (0.38, 0.53, 0.24))]


def build_Core_Drum(base="PaintBlue"):
    """Ядро-бочка из-под масла: крашеная жесть с зигами-рёбрами, железные закатки, латунные пробки на крышке, широкий пояс
    цвета игрока, латка с окошком Ядра, хомуты плеч."""
    R = 0.176
    def rib(yc):   # зиг — выкатанное ребро жёсткости
        return [(R, yc + 0.02), (R + 0.003, yc + 0.012), (R + 0.01, yc + 0.005), (R + 0.01, yc - 0.005), (R + 0.003, yc - 0.012),
                (R, yc - 0.02)]

    prof = [(0.0, 0.234), (0.166, 0.234), (0.171, 0.238), (R, 0.232)] + rib(0.125) + rib(-0.125)
    prof += [(R, -0.232), (0.171, -0.238), (0.166, -0.234), (0.0, -0.234)]
    objs = [fin(revolve("CD_Shell", prof, "Base_" + base, 28), 0.0, angle=45.0, uv="cyl")]
    for y in (0.242, -0.242):
        objs.append(fin(torus("CD_Chime", (0.0, y, 0.0), R - 0.002, 0.011, "Iron", 'XZ', 28, 5), angle=80))
    # пояса цвета игрока (BODY_KIT.md §1, «Цвет игрока на ядре»): широкий — от верхнего зига до закатки крышки, узкий — у дна
    objs.append(_player_band("CD_Stripe", 0.226, 0.147, lambda y: R, lift=0.003, segs=28))
    objs.append(_player_band("CD_StripeLow", -0.186, -0.226, lambda y: R, lift=0.003, segs=28))
    # пробки: большая (латунь, шестигранник) и малая отдушина
    for (x, z), rr, hh in (((0.098, 0.06), 0.03, 0.034), ((-0.1, -0.055), 0.019, 0.024)):
        objs.append(fin(torus("CD_BungRing", (x, 0.235, z), rr + 0.006, 0.005, "Iron", 'XZ', 12, 4), angle=80))
        objs.append(fin(revolve("CD_Bung", [(0.0, 0.228), (rr, 0.228), (rr, 0.234 + hh * 0.6), (rr * 0.85, 0.234 + hh),
                                            (0.0, 0.234 + hh)], "Brass", 6, phase=math.pi / 6), 0.002, 1))
        objs.append(fin(revolve("CD_BungTop", [(0.0, 0.234 + hh - 0.002), (rr * 0.55, 0.234 + hh - 0.002), (rr * 0.5, 0.234 + hh + 0.006),
                                               (0.0, 0.234 + hh + 0.006)], "Brass", 12), 0.0, angle=50))
    # латка на заклёпках с окошком Ядра
    bend = 1.2
    objs.append(fin(extrude2d("CD_Patch", superellipse(0.0, 0.0, 0.1, 0.09, 28, 4.0), 0.136, 0.181, "Iron", bend=bend), 0.003, 1))
    for x, y in superellipse(0.0, 0.0, 0.088, 0.078, 10, 4.0):
        objs.append(fin(stud("CD_PatchRivet", (x, y, 0.181 - bend * x * x), (x * bend * 2.0, 0.0, 1.0), "Steel", 0.0055, 0.004, 6)))
    objs += porthole("CD_Core", (0.0, 0.0, 0.184), 0.052)
    # шея — фланец на крышке; плечи — хомуты на верхней закатке; бока — бобышки; бёдра — бобышки под дном
    objs += _boss("CD_Neck", (0.0, 0.236, 0.0), (0, 1, 0), 0.054, 0.034, bolts=5)
    for sx in (-1, 1):
        objs.append(rbox("CD_ShoulderClamp", (0.072, 0.066, 0.078), "Iron", (sx * 0.19, 0.246, 0.0), 0.012, 2))
        objs.append(fin(stud("CD_ClampBolt", (sx * 0.19, 0.246, 0.04), (0, 0, 1), "Steel", 0.009, 0.006, 6)))
        objs += _boss("CD_Side", (sx * 0.172, 0.0, 0.0), (sx, 0, 0), 0.04, 0.028)
        objs += _boss("CD_Hip", (sx * 0.1, -0.236, 0.0), (0, -1, 0), 0.048, 0.024, segs=12)
    pos = {"Neck": (0.0, 0.295, 0.0), "Shoulder_L": (0.222, 0.262, 0.0), "Hip_L": (0.1, -0.278, 0.0), "Side_L": (0.206, 0.0, 0.0),
           "Back": (0.0, 0.2, -0.186)}
    objs.append(rbox("CD_BackClamp", (0.05, 0.05, 0.02), "Iron", (0.0, 0.2, -0.178), 0.006, 2))
    return objs, _anchors(pos) + [shape_cyl("Torso", (0.0, 0.0, 0.0), 0.18, 0.5)]


def build_Core_Cage(base="Iron"):
    """Ядро-клетка (лор: Ядро на виду): железная птичья клетка на цоколе, за прутьями — большой светящийся шар Ядра
    в лапках-держателях; коромысло плеч, обручи и пояс цоколя цвета игрока, окошко Ядра на цоколе."""
    Rb, y_lo, y_arc, y_top, r_hub = 0.172, -0.15, 0.1, 0.25, 0.034

    def bar_path(a):
        pts = [(Rb * math.sin(a), y, Rb * math.cos(a)) for y in (y_lo, -0.02, y_arc)]
        for k in range(1, 8):
            t = math.pi / 2 * k / 8
            r = r_hub + (Rb - r_hub) * math.cos(t)
            pts.append((r * math.sin(a), y_arc + (y_top - y_arc) * math.sin(t), r * math.cos(a)))
        return pts

    base_m = "Base_" + base
    objs = [fin(revolve("CG_Plinth", [(0.0, -0.264), (0.172, -0.264), (0.192, -0.257), (0.197, -0.242), (0.188, -0.228),
                                      (0.186, -0.172), (0.195, -0.162), (0.195, -0.15), (0.182, -0.143), (0.0, -0.143)],
                        base_m, 28), 0.0, angle=50.0, uv="cyl")]
    # прутья: 10 делений, бока (±X) — плоские стойки под бобышки Side, спереди по центру прутка нет (шар виден)
    for k in range(10):
        a = math.radians(18.0 + 36.0 * k)
        if abs(math.sin(a)) > 0.999:
            continue
        objs.append(fin(sweep("CG_Bar", bar_path(a), 0.0085, base_m, sides=6), angle=60))
    for sx in (-1, 1):
        objs.append(fin(sweep("CG_Stile", bar_path(sx * math.pi / 2), 0.014, base_m, sides=4, phase=math.pi / 4), angle=40))
        objs += _boss("CG_Side", (sx * (Rb - 0.004), 0.0, 0.0), (sx, 0, 0), 0.04, 0.028)
    back = bar_path(math.pi)[2:]
    objs.append(fin(sweep("CG_BackStile", back, 0.012, base_m, sides=4, phase=math.pi / 4), angle=40))
    for y, mat, rr in ((y_lo + 0.012, base_m, 0.011), (0.03, "Shirt_Kit", 0.012)):
        objs.append(fin(torus("CG_Hoop", (0.0, y, 0.0), Rb, rr, mat, 'XZ', 24, 5), angle=80))

    def bar_r(y):
        """Внешний радиус прутьев на высоте y (прямые до y_arc, выше — купол)."""
        if y <= y_arc:
            return Rb + 0.0085
        s = min((y - y_arc) / (y_top - y_arc), 1.0)
        return r_hub + (Rb - r_hub) * math.cos(math.asin(s)) + 0.0085

    # цвет игрока (BODY_KIT.md §1, «Цвет игрока на ядре»): широкий обруч на плече купола (вместо железного обруча y_arc) и
    # пояс на цоколе (табличка с окошком Ядра — поверх него)
    objs.append(_player_band("CG_PlayerHoop", 0.132, 0.07, bar_r, lift=0.003, segs=24, sink=0.017))
    objs.append(_player_band("CG_PlayerPlinth", -0.174, -0.226, lambda y: 0.187, lift=0.003, segs=28))
    # купол-ступица и горловина шеи
    objs.append(fin(revolve("CG_Hub", [(0.0, 0.272), (0.03, 0.27), (0.048, 0.258), (0.052, 0.244), (0.044, 0.234), (0.0, 0.234)],
                            base_m, 20), 0.0, angle=50))
    objs += _boss("CG_Neck", (0.0, 0.268, 0.0), (0, 1, 0), 0.04, 0.018)
    # коромысло плеч сквозь купол: шары плеч садятся на его торцы
    yy = 0.232
    objs.append(fin(sweep("CG_Yoke", [(-0.2, yy, 0.0), (0.2, yy, 0.0)], 0.017, "Iron", sides=10), angle=50, uv="cyl"))
    for sx in (-1, 1):
        objs += _boss("CG_Shoulder", (sx * 0.176, yy, 0.0), (sx, 0, 0), 0.042, 0.022)
        objs += _boss("CG_Hip", (sx * 0.1, -0.26, 0.0), (0, -1, 0), 0.046, 0.02, segs=12)
    objs.append(fin(revolve("CG_BackPad", [(0.0, -0.01), (0.028, -0.01), (0.028, 0.008), (0.022, 0.014), (0.0, 0.014)], "Iron", 14,
                            align_y((0, 0, -1), (0.0, 0.2, -0.128))), 0.002, 1))
    # шар Ядра на чаше-держателе с четырьмя лапками
    orb_c, orb_r = Vector((0.0, -0.005, 0.0)), 0.104
    objs.append(fin(sphere("CG_Orb", orb_r, tuple(orb_c), "CoreGlow", 20, 10), angle=80))
    objs.append(fin(revolve("CG_Cradle", [(0.0, -0.143), (0.04, -0.143), (0.024, -0.13), (0.022, -0.116), (0.05, -0.104),
                                          (0.066, -0.084), (0.058, -0.08), (0.0, -0.1)], "Iron", 20), 0.0, angle=50))
    for k in range(4):
        a = TAU * k / 4 + math.pi / 4
        pts = []
        for i in range(5):
            t = math.radians(-55.0 + 70.0 * i / 4)
            r = orb_r + 0.006
            pts.append((r * math.cos(t) * math.sin(a), orb_c.y + r * math.sin(t), r * math.cos(t) * math.cos(a)))
        objs.append(fin(sweep("CG_Prong", pts, [0.009, 0.008, 0.007, 0.006, 0.005], "Iron", sides=5), angle=60))
    # окошко Ядра на цоколе — на плоской табличке
    objs.append(rbox("CG_Plate", (0.13, 0.104, 0.03), "Brass", (0.0, -0.204, 0.184), 0.008, 2))
    objs += porthole("CG_Core", (0.0, -0.204, 0.204), 0.036)
    pos = {"Neck": (0.0, 0.3, 0.0), "Shoulder_L": (0.226, yy, 0.0), "Hip_L": (0.1, -0.29, 0.0), "Side_L": (0.21, 0.0, 0.0),
           "Back": (0.0, 0.2, -0.148)}
    return objs, _anchors(pos) + [shape_cyl("Torso", (0.0, 0.0, 0.0), 0.185, 0.53)]


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3): ядро бесплатно по энергии, масса как у торса v3 (12 кг) ± форма и материал;
# удар ядром — Tuning.BODY_MULT["Torso"] × материал (builder), своего body_mult нет
META = {
    "Core_Barrel": {"kind": "core", "title": "Ядро-бочка", "mass": 12.0, "energy": 0},
    "Core_Crate": {"kind": "core", "title": "Ядро-ящик", "mass": 11.0, "energy": 0},
    "Core_Ball": {"kind": "core", "title": "Ядро-хаб", "mass": 14.0, "energy": 0},
    "Core_Boiler": {"kind": "core", "title": "Ядро-котёл", "mass": 18.0, "energy": 0},
    "Core_Toy": {"kind": "core", "title": "Ядро-игрушка", "mass": 11.0, "energy": 0},
    "Core_Drum": {"kind": "core", "title": "Ядро-бочка из-под масла", "mass": 13.0, "energy": 0},
    "Core_Cage": {"kind": "core", "title": "Ядро-клетка", "mass": 14.0, "energy": 0},
}
