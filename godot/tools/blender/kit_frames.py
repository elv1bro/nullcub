"""Рама и разветвители на пять и на два разъёма (06.10.2026) — продолжение «невозможных конструкций» про-лиги (Hub_ProTee,
Limb_ProSpine в kit_pro.py; docs/plan-demo/KIT_SETS.md, раздел «Разветвители»). Контракт — как у остального кита
(docs/plan-demo/BODY_KIT.md): геометрия в координатах Godot, origin = Socket, деталь растёт в −Y.

Язык — про-лиги: тёмная труба-рама (Iron, раскосы и болты — Steel), кремовые кольца, скорлупы и косынки (Base_<Mat> — ось
материалов), латунные ободы гнёзд, цвет игрока Shirt_Kit (поясок на шейке, полосы на косынках), карбоновый узел с голубой линзой
(роли Pro_Carbon / Pro_Glow — из kit_pro, .tres пишет Godot-builder по PRO_MATS).

Якоря — только имена контракта: End (продолжает цепочку), Side_L / Side_R (боковые выходы, группа Hip) и вторая пара боковых
SideB_L / SideB_R (ведёт себя как Side_*), Deco (броня и модули). Угол якоря — поворот вокруг Z: ребёнок растёт по
(sin a, −cos a, 0), +угол — к +X (левая сторона куклы); _R — зеркало _L (x → −x, угол → −угол). Как у Hub_ProTee, якорь стоит
на JOINT_GAP дальше торца своего гнезда: шар шарнира садится на латунный обод."""
import math

from mathutils import Vector

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
import craft_parts as K  # noqa: F401
from kit_ends import _zrev
from kit_pro import _lens, _mats, _socket_boss

JOINT_GAP = 0.03    # от торца гнезда до якоря (как у Hub_ProTee: TEE_D − (TEE_D − 0.03))


def _down(deg):
    """Направление роста ребёнка якоря с углом deg: 0 — вниз, +90 — к +X."""
    a = math.radians(deg)
    return Vector((math.sin(a), -math.cos(a), 0.0))


def _stem(prefix, y0, y1, r, band_y):
    """Шейка разветвителя: стальная шейка от сокета вниз, тёмная обойма под шар сустава, поясок цвета игрока (как у Hub_ProTee)."""
    objs = [fin(revolve(prefix + "_Stem", [(0.0, y0), (r * 0.8, y0), (r * 0.84, y1), (0.0, y1)], "Iron", 14), uv="cyl")]
    objs += ferrule(prefix + "_TopCap", -0.03, -0.05, 0.043, rivets=0)
    objs.append(band(prefix + "_Stripe", band_y, r * 0.93, 0.011, "Shirt_Kit"))
    return objs


def _knot(prefix, c, R, b, cheeks=True, segs=16):
    """Узел разветвителя (как у Hub_ProTee): карбоновый шар, кремовая обойма-пояс в плоскости кадра, щёчки спереди и сзади,
    голубая линза в латунном ободе."""
    c = Vector(c)
    objs = [fin(sphere(prefix + "_Ball", R, tuple(c), "Pro_Carbon", segs, segs // 2), angle=60.0, uv="cyl")]
    objs.append(fin(torus(prefix + "_Cage", tuple(c), R + 0.004, 0.013, b, 'XY', 24, 6), angle=70.0))
    if cheeks:
        for sz in (-1, 1):
            objs.append(fin(revolve(prefix + "_Cheek", [(0.0, 0.0), (R * 0.62, 0.0), (R * 0.56, 0.012), (R * 0.3, 0.02), (0.0, 0.022)],
                                    b, 14, align_y((0.0, 0.0, float(sz)), c + Vector((0.0, 0.0, sz * (R - 0.012))))), 0.002, 1,
                            uv="cyl"))
    objs += _lens(prefix, c + Vector((0.0, 0.0, R + 0.008)), (0.0, 0.0, 1.0), 0.02, rim="Brass", segs=12)
    return objs


# ---------------------------------------------------------------------------------------------------------------------------------
# Рама — плоское шасси на пять выходов
# ---------------------------------------------------------------------------------------------------------------------------------
FRAME_RC = 0.045       # радиус скругления углов рамы (по оси трубы)
FRAME_SIDEB = 40.0     # нижние угловые выходы — на ±40° от оси вниз
FRAME_GUSSET = 0.12    # катет косынки (от воображаемого угла рамы)


def _rrect(hw, yt, yb, rc, n=4):
    """Осевая линия трубы рамы: прямоугольник ±hw × [yb, yt] со скруглёнными углами, против часовой от левого (+X) верхнего."""
    pts = []
    for cx, cy, a0 in ((hw - rc, yt - rc, 0.0), (-hw + rc, yt - rc, 90.0), (-hw + rc, yb + rc, 180.0), (hw - rc, yb + rc, 270.0)):
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append(Vector((cx + rc * math.cos(a), cy + rc * math.sin(a), 0.0)))
    return pts


def _corner_mid(hw, yE, sx, sy, rc):
    """Середина дуги угла рамы (sx, sy = ±1; yE — верхняя или нижняя ось)."""
    k = rc * (1.0 - math.cos(math.radians(45.0)))
    return Vector((sx * (hw - k), yE - sy * k, 0.0))


def build_Limb_Frame(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintWhite"):
    """Рама — плоское шасси на пять выходов: от сокета вниз шейка с пояском цвета игрока и кремовым хомутом на верхней трубе,
    прямоугольник из тёмной трубы со скруглёнными углами, в углах кремовые косынки с полосой цвета игрока и болтом; по оси —
    стойка, крест-накрест — стальные раскосы, в центре карбоновый барабан в кремовом кольце с голубой линзой. Пять гнёзд с
    латунными ободами: вниз из середины нижней трубы (End), вбок из середины боковых (Side_L / Side_R, 90°) и из нижних углов
    вниз-наружу (SideB_L / SideB_R, ±40°). Deco — на оси у верхней трубы: броня и модули висят по центру рамы, перед барабаном
    (лицо барабана на z ≈ 0.04, как поверхность конечности)."""
    _mats()
    b = "Base_" + base
    tr = r * 0.36                                  # радиус трубы рамы: S 0.021, L 0.027
    hw = 0.21 + (L - 0.30) * 0.2                   # полуширина по оси трубы: S 0.21 (габарит 0.46), L 0.234
    ya = ja * 0.6                                  # верх шейки — под шар сустава родителя (как у конечностей)
    yt = -ya - 0.045                               # ось верхней трубы
    yb = yt - L                                    # ось нижней трубы: высота по осям = L (S 0.30, габарит 0.34)
    ym = (yt + yb) / 2.0
    rc = FRAME_RC
    # шейка: обойма под шар, стальная шейка, поясок цвета игрока, кремовый хомут на верхней трубе
    objs = [fin(revolve("LFR_Stem", [(0.0, -ya + 0.008), (r * 0.7, -ya + 0.008), (r * 0.78, -ya - 0.004), (r * 0.78, -ya - 0.018),
                                     (r * 0.55, -ya - 0.024), (r * 0.5, yt), (0.0, yt)], "Iron", 14), uv="cyl")]
    ys = -ya - 0.032
    objs.append(fin(revolve("LFR_Stripe", [(r * 0.5, ys + 0.0055), (r * 0.58, ys + 0.0035), (r * 0.58, ys - 0.0035), (r * 0.5, ys - 0.0055)],
                            "Shirt_Kit", 14, closed=True), angle=50.0, uv="cyl"))
    objs.append(rbox("LFR_Clamp", (0.1, tr * 2.0 + 0.022, tr * 2.0 + 0.014), b, (0.0, yt, 0.0), 0.01, 2))
    # труба рамы, стойка по оси, раскосы крест-накрест
    objs.append(fin(sweep("LFR_Rail", _rrect(hw, yt, yb, rc), tr, "Iron", sides=8, closed=True), angle=50.0))
    objs.append(fin(sweep("LFR_Post", [(0.0, yt, 0.0), (0.0, yb, 0.0)], tr * 0.72, "Iron", sides=8), angle=50.0))
    for sx in (-1.0, 1.0):
        p0, p1 = _corner_mid(hw, yt, sx, 1.0, rc), _corner_mid(hw, yb, -sx, -1.0, rc)
        objs.append(fin(sweep("LFR_Brace", [p0 + Vector((0.0, 0.0, -0.004)), p1 + Vector((0.0, 0.0, -0.004))], tr * 0.5, "Steel",
                              sides=6), angle=50.0))
    # косынки в углах: кромки по оси трубы (прячутся в ней), внутренняя кромка — гипотенуза; полоса цвета игрока вдоль неё
    g = min(FRAME_GUSSET, L / 2.0 - 0.045)         # нижний край косынки не заходит под стакан бокового гнезда
    for sx in (-1.0, 1.0):
        for sy, yE in ((1.0, yt), (-1.0, yb)):
            V = Vector((sx * hw, yE, 0.0))
            A = Vector((sx * (hw - g), yE, 0.0))
            B = Vector((sx * hw, yE - sy * g, 0.0))
            arc = [(sx * (hw - rc + rc * math.cos(math.radians(90.0 * i / 4))), yE - sy * (rc - rc * math.sin(math.radians(90.0 * i / 4))))
                   for i in range(5)]
            poly = [(B.x, B.y)] + arc + [(A.x, A.y)]
            objs.append(fin(extrude2d("LFR_Gusset", poly, -0.007, 0.007, b), 0.003, 1, angle=40.0))
            s0, s1 = 0.8, 0.92
            stripe = [V + (A - V) * s1, V + (B - V) * s1, V + (B - V) * s0, V + (A - V) * s0]
            objs.append(fin(extrude2d("LFR_GussetStripe", [(p.x, p.y) for p in stripe], 0.004, 0.0105, "Shirt_Kit"), angle=40.0))
            rv = V + ((A - V) + (B - V)) * 0.33
            objs.append(fin(stud("LFR_GussetBolt", (rv.x, rv.y, 0.007), (0, 0, 1), "Steel", 0.0075, 0.005, 6)))
    # центральный узел: карбоновый барабан (ось к камере) в кремовом кольце, на лице — кольцо цвета игрока вокруг линзы
    c = Vector((0.0, ym, 0.0))
    objs.append(fin(_zrev("LFR_Drum", [(0.0, -0.03), (0.05, -0.03), (0.054, -0.02), (0.054, 0.03), (0.047, 0.04), (0.0, 0.04)],
                          "Pro_Carbon", tuple(c), 20), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(torus("LFR_Ring", tuple(c), 0.072, 0.016, b, 'XY', 24, 6), angle=70.0))
    objs.append(fin(_zrev("LFR_DrumStripe", [(0.032, 0.037), (0.045, 0.037), (0.045, 0.0435), (0.032, 0.0435)], "Shirt_Kit",
                          tuple(c), 16, closed=True), angle=50.0, uv="cyl", axis='Z'))
    objs += _lens("LFR", c + Vector((0.0, 0.0, 0.04)), (0.0, 0.0, 1.0), 0.022, rim="Brass", segs=14)
    # гнёзда и якоря: от оси трубы наружу на tr + 0.032 (торец), якорь — ещё на JOINT_GAP
    r1 = tr + 0.032
    D = r1 + JOINT_GAP
    empties = [socket(), anchor("Deco", (0.0, yt - tr - 0.012, 0.0))]
    outs = [("End", Vector((0.0, yb, 0.0)), 0.0),
            ("Side_L", Vector((hw, ym, 0.0)), 90.0), ("Side_R", Vector((-hw, ym, 0.0)), -90.0),
            ("SideB_L", _corner_mid(hw, yb, 1.0, -1.0, rc), FRAME_SIDEB), ("SideB_R", _corner_mid(hw, yb, -1.0, -1.0, rc), -FRAME_SIDEB)]
    for nm, p, deg in outs:
        d = _down(deg)
        objs += _socket_boss("LFR_" + nm, p, d, -0.004, r1)
        empties.append(anchor(nm, tuple(p + d * D), deg))
    empties.append(shape_box("Frame", (0.0, ym, 0.0), (2.0 * (hw + tr), yt - yb + 2.0 * tr, 0.09)))
    empties.append(shape_box("Stem", (0.0, (-ya + yt) / 2.0, 0.0), (r * 1.4, -ya - yt, r * 1.4)))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# Звезда — узел на пять выходов
# ---------------------------------------------------------------------------------------------------------------------------------
STAR_C = (0.0, -0.135, 0.0)   # центр узла: ниже, чем у тройника, — верхние выходы (±120°) не задевают шар сустава над сокетом
STAR_R = 0.066
STAR_D = 0.135                # от центра до якоря: соседние шары шарниров (60° между выходами) не налезают друг на друга,
                              # стаканы длиннее, чем у тройника, — лучи звезды разделены зазорами
STAR_OUTS = (("End", 0.0), ("Side_L", 60.0), ("Side_R", -60.0), ("SideB_L", 120.0), ("SideB_R", -120.0))


def build_Hub_Star(base="PaintWhite"):
    """Звезда — разветвитель на пять выходов: шейка с пояском цвета игрока, карбоновый шар-узел в кремовой обойме с щёчками и
    голубой линзой, пять коротких кремовых стаканов-лучей с латунными ободами через каждые 60° — вниз (End), на ±60°
    (Side_L / Side_R) и на ±120°, вверх-наружу (SideB_L / SideB_R); вместе с шейкой — шестилучевая звезда."""
    _mats()
    b = "Base_" + base
    c = Vector(STAR_C)
    R = STAR_R
    objs = _stem("HST", -0.036, c.y + R - 0.01, 0.043, -0.058)
    objs += _knot("HST", c, R, b)
    empties = [socket(), shape_sphere("Hub", tuple(c), R + 0.018)]
    for nm, deg in STAR_OUTS:
        d = _down(deg)
        objs += _socket_boss("HST_" + nm, c, d, R - 0.012, STAR_D - JOINT_GAP, mat=b)   # лучи — кремовые: звезда читается на тёмном шаре
        empties.append(anchor(nm, tuple(c + d * STAR_D), deg))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# Развилка — рогатка на два выхода
# ---------------------------------------------------------------------------------------------------------------------------------
FORK_C = (0.0, -0.1, 0.0)
FORK_R = 0.046
FORK_D = 0.21          # от центра узла до якоря вдоль рога
FORK_FAN = 30.0        # рога — на ±30° от оси вниз


def build_Hub_Fork(base="PaintWhite"):
    """Развилка — рогатка на два выхода: шейка с пояском цвета игрока, карбоновый узел в кремовой обойме с голубой линзой,
    два рога из тёмной трубы на ±30° от оси вниз, между ними под узлом — кремовая перемычка-серп на болте; на внешней части рогов
    кремовые скорлупы с полосой цвета игрока, на концах — гнёзда с латунными ободами (Side_L / Side_R). Без End: цепочка
    раздваивается."""
    _mats()
    b = "Base_" + base
    c = Vector(FORK_C)
    R = FORK_R
    objs = _stem("HFK", -0.036, c.y + R - 0.01, 0.043, -0.058)
    objs += _knot("HFK", c, R, b, cheeks=False)
    empties = [socket(), shape_sphere("Hub", tuple(c), R + 0.012)]
    sb = FORK_D - 0.075                              # начало стакана гнезда вдоль рога
    g0 = 0.085                                       # начало скорлупы (до неё рог открыт, видна тёмная труба и перемычка)
    h = sb + 0.004 - g0
    for nm, deg in (("Side_L", FORK_FAN), ("Side_R", -FORK_FAN)):
        d = _down(deg)
        objs.append(fin(sweep("HFK_Horn", [c + d * (R * 0.4), c + d * (sb + 0.01)], 0.019, "Iron", sides=10), angle=50.0))
        xf = align_y(d, c + d * g0)
        objs.append(fin(revolve("HFK_Shell", [(0.022, 0.0), (0.028, 0.007), (0.0295, h * 0.5), (0.027, h - 0.004), (0.024, h)], b, 14, xf),
                        0.002, 1, angle=40.0, uv="cyl"))
        ys = h * 0.42
        objs.append(fin(revolve("HFK_ShellStripe", [(0.0275, ys - 0.011), (0.032, ys - 0.008), (0.032, ys + 0.008), (0.0275, ys + 0.011)],
                                "Shirt_Kit", 14, xf, closed=True), angle=50.0, uv="cyl"))
        objs += _socket_boss("HFK_" + nm, c, d, sb, FORK_D - JOINT_GAP)
        empties.append(anchor(nm, tuple(c + d * FORK_D), deg))
        empties.append(shape_capsule("Horn" + nm[-2:], tuple(c + d * (FORK_D * 0.55)), 0.03, FORK_D * 0.75, deg))
    # перемычка-серп между рогами под узлом: кромки по осям рогов (прячутся в трубе), низ — вогнутая дуга
    dl, dr = _down(FORK_FAN), _down(-FORK_FAN)
    a, e = c + dl * 0.11, c + dr * 0.11
    m = c + Vector((0.0, -0.06, 0.0))
    arc = [a * (1 - t) ** 2 + m * 2 * t * (1 - t) + e * t * t for t in (k / 6 for k in range(7))]
    web = [c + dl * (R * 0.8)] + arc + [c + dr * (R * 0.8)]
    objs.append(fin(extrude2d("HFK_Web", [(p.x, p.y) for p in web], -0.01, 0.01, b), 0.003, 1, angle=40.0))
    objs.append(fin(stud("HFK_WebBolt", (0.0, c.y - 0.062, 0.01), (0, 0, 1), "Steel", 0.0075, 0.005, 6)))
    return objs, empties


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3). Рама — конечность (полка «Конечности», размеры S / L по body_kit.sized,
# масса и энергия у обоих размеров одни), звезда и развилка — суставы (полка «Шарниры»)
META = {
    "Limb_Frame": {"kind": "limb", "title": "Рама", "mass": 4.0, "energy": 9},
    "Hub_Star": {"kind": "joint", "title": "Звезда", "mass": 2.6, "energy": 5},
    "Hub_Fork": {"kind": "joint", "title": "Развилка", "mass": 1.8, "energy": 3},
}
