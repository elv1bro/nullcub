"""Детали NULL League — части других цивилизаций лиги (листы автора «NULL League parts» / «Extraterrestrial parts», 30.09.2026;
описание — docs/plan-demo/ART_NULL.md, листы 3–4; лор — правило трофея, LORE_NULL.md). Первая партия на вкус облачной сессии:
3 головы, 2 ядра, 2 конечности, кисть, 2 навершия оружия, 2 детали декора / брони.

Контракт — как у остального кита (docs/plan-demo/BODY_KIT.md): стандартные сокеты и якоря, Base_<Mat> — корпус на оси материалов
(физика по MaterialDef), у голов FacePlate (фото игрока — в «глазу» / окне шлема), у ядер пояс Shirt_Kit, у конечностей полоска.
Чужие материалы — фиксированные роли League_* (не перекрашиваются, .tres пишет tools/build_league_mats.gd):
    League_Void     «пустотный металл» — почти чёрный глянцевый с фиолетовым отливом (обоймы, рамы, лезвия)
    League_Glow     фиолетовое свечение поля (зрачки, узлы, кромки)
    League_Cyan     голубое свечение (сенсоры, прожилки кристаллов)
    League_Crystal  энергокристалл — полупрозрачный голубой с внутренним светом
    League_Gold     «гармонический металл» — яркое золото (кольца, когти)
Особых механик (гравитационное ядро, фаза, щит) пока нет — только форма, масса и энергия; hit_mult = 1.0 (таблица kit_probe).
"""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
import common as C
import craft_parts as K
from kit_cores import _player_band, _rot
from kit_weapons import _collar

# роль → (база RGBA, шероховатость, металличность, эмиссия RGB | None, сила эмиссии в кадре Blender, альфа)
LEAGUE_MATS = {
    "League_Void": ((0.02, 0.017, 0.03, 1.0), 0.22, 0.85, None, 0.0, 1.0),
    "League_Glow": ((0.25, 0.08, 0.5, 1.0), 0.3, 0.0, (0.62, 0.22, 1.0), 1.6, 1.0),
    "League_Cyan": ((0.1, 0.4, 0.5, 1.0), 0.3, 0.0, (0.25, 0.85, 1.0), 1.4, 1.0),
    "League_Crystal": ((0.35, 0.72, 0.95, 1.0), 0.05, 0.0, (0.2, 0.6, 1.0), 0.6, 0.55),
    "League_Gold": ((0.85, 0.58, 0.2, 1.0), 0.28, 0.9, None, 0.0, 1.0),
}


def _mats():
    """Материалы ролей League_* для этого запуска Blender: в экспорте — плоские (имя = роль, настоящие ставит Godot),
    в кадре — с эмиссией и прозрачностью кристалла. Кэш craft_parts (K._MATS) чистится на каждую деталь — вызывать в builder-е."""
    for role, (base, rough, metal, em, es, alpha) in LEAGUE_MATS.items():
        if role in K._MATS:
            continue
        if K.FORCE_FLAT or em is None:
            m = C.material(role, base, rough, metal)
        else:
            m = C.material(role, base, rough, metal, emission=em + (1.0,), emission_strength=es)
        if alpha < 1.0 and not K.FORCE_FLAT:
            m.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value = alpha
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = 'BLENDED'
        m.use_backface_culling = True
        K._MATS[role] = m


def _shard(name, base_pos, direction, length, radius, mat, sides=6, taper=0.55, twist=0.0):
    """Кристалл: n-гранная призма от base_pos по direction, сужается (taper) и сходится в острие."""
    d = Vector(direction).normalized()
    xf = align_y(d, base_pos)
    rings = []
    for k, (t, rr) in enumerate(((0.0, radius * 0.8), (0.08, radius), (0.7, radius * taper))):
        y = length * t
        rings.append([tuple(xf @ Vector((rr * math.cos(2 * math.pi * i / sides + twist * t), y, rr * math.sin(2 * math.pi * i / sides + twist * t))))
                      for i in range(sides)])
    tip = tuple(xf @ Vector((0.0, length, 0.0)))
    return loft(name, rings, mat, caps=True, pole1=tip)


def _bosses(prefix, R, anchors, mat="League_Void"):
    """Гнёзда-бобышки на якорях шара-ядра (как Core_Ball): (имя, угол в XY, расстояние якоря)."""
    objs, empties = [], []
    for nm, deg, dist in anchors:
        d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))
        h = 0.045 + (dist - 0.262)
        objs.append(fin(revolve(prefix + "_Boss", [(0.0, 0.0), (0.055, 0.0), (0.055, h - 0.014), (0.046, h), (0.0, h)], mat, 18,
                                align_y(d, d * (R - 0.012))), 0.004, 1, uv="cyl"))
        objs.append(fin(revolve(prefix + "_BossRing", [(0.058, h - 0.03), (0.06, h - 0.024), (0.058, h - 0.018)], "League_Cyan", 18,
                                align_y(d, d * (R - 0.012)), closed=True), angle=80))
        empties.append(anchor(nm, tuple(d * dist), _rot(nm)))
    return objs, empties


BALL_ANCHORS = [("Neck", 90.0, 0.262), ("Shoulder_L", 46.4, 0.283), ("Shoulder_R", 133.6, 0.283), ("Side_L", -5.0, 0.262),
                ("Side_R", 185.0, 0.262), ("Hip_L", -62.0, 0.262), ("Hip_R", -118.0, 0.262)]


# ---------------------------------------------------------------------------------------------------------------------------------
# головы: FacePlate — фото игрока (правило вещания: табло показывает лицо, LORE_NULL.md)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Head_LeagueEye(base="PaintWhite"):
    """Голова-око: яйцо-панцирь с одним огромным объективом спереди — фото игрока внутри линзы, в тёмной обойме с голубым
    кольцом; два стреловидных «уха»-сенсора назад, сенсор на макушке."""
    _mats()
    prof = [(0.0, 0.035), (0.07, 0.045), (0.12, 0.08), (0.148, 0.14), (0.155, 0.2), (0.148, 0.26), (0.125, 0.32), (0.085, 0.36),
            (0.04, 0.378), (0.0, 0.382)]
    shell = revolve("HLE_Shell", prof, "Base_" + base, 32)
    cut_sphere(shell, (0.0, 0.205, 0.215), 0.1, 28)
    objs = [fin(shell, 0.0, angle=50.0, uv="cyl")]
    objs.append(fin(torus("HLE_Bezel", (0.0, 0.205, 0.138), 0.074, 0.016, "League_Void", 'XY', 40, 10), angle=80))
    objs.append(torus("HLE_Glow", (0.0, 0.205, 0.146), 0.062, 0.004, "League_Cyan", 'XY', 40, 6))
    for sx in (-1, 1):
        ear = [(0.0, 0.0), (0.035, 0.02), (0.13, 0.05), (0.15, 0.045), (0.05, -0.01), (0.0, -0.02)]
        xf = T((sx * 0.135, 0.25, -0.02)) @ Matrix.Rotation(math.radians(-sx * 90.0 + sx * 25.0), 4, 'Y') @ Rz(sx * 18.0)
        pts = [(x, y) for x, y in ear]
        objs.append(fin(extrude2d("HLE_Ear", pts, -0.008, 0.008, "League_Void", xf=xf), 0.003, 1, angle=40.0))
        objs.append(fin(sphere("HLE_EarTip", 0.009, tuple(xf @ Vector((0.14, 0.047, 0.0))), "League_Cyan", 8, 4), angle=80))
    objs.append(fin(revolve("HLE_Stalk", [(0.012, 0.37), (0.008, 0.405), (0.0, 0.41)], "League_Void", 10), angle=60))
    objs.append(sphere("HLE_Sensor", 0.014, (0.0, 0.41, 0.0), "League_Cyan", 10, 5))
    objs += neck_stub("HLE")
    face = face_plate("FacePlate", (0.0, 0.205, 0.119), 0.108, 0.108, cols=10, rows=10, round_n=2.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.4, 0.0), 180.0), shape_sphere("Head", (0.0, 0.205, 0.0), 0.16)]
    return objs, empties, [face]


def build_Head_LeagueCrystal(base="Iron"):
    """Кристальная голова: тёмная маска-обойма с окном под фото, из неё растёт друза энергокристаллов (главный и два боковых),
    золотой обод по краю маски, внутри кристалла светится голубое ядро."""
    _mats()
    mask = rbox("HLK_Mask", (0.25, 0.17, 0.21), "Base_" + base, (0.0, 0.125, 0.0), 0.03, 3)
    cut_box(mask, (0.0, 0.125, 0.11), (0.17, 0.11, 0.04))
    objs = [fin(mask, 0.0, angle=40.0)]
    objs.append(rounded_frame("HLK_Frame", (0.0, 0.125), 0.09, 0.058, 0.007, "League_Gold", 0.101))
    objs.append(fin(revolve("HLK_Rim", [(0.1, 0.205), (0.118, 0.205), (0.118, 0.222), (0.1, 0.226)], "League_Gold", 24, closed=True),
                    0.002, 1, uv="cyl"))
    objs.append(fin(_shard("HLK_Main", (0.0, 0.2, 0.0), (0.0, 1.0, 0.0), 0.33, 0.085, "League_Crystal", twist=0.4), angle=20.0))
    for sx in (-1, 1):
        objs.append(fin(_shard("HLK_Side", (sx * 0.07, 0.205, 0.02), (sx * 0.55, 1.0, 0.12), 0.17, 0.042, "League_Crystal"),
                        angle=20.0))
    objs.append(sphere("HLK_Core", 0.035, (0.0, 0.3, 0.0), "League_Cyan", 12, 6))
    objs += neck_stub("HLK")
    face = face_plate("FacePlate", (0.0, 0.125, 0.093), 0.165, 0.104, cols=10, rows=6, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.53, 0.0), 180.0), shape_box("Head", (0.0, 0.2, 0.0), (0.25, 0.36, 0.21))]
    return objs, empties, [face]


def build_Head_LeagueRing(base="PaintWhite"):
    """Голова с гало: гладкая сфера с плоским окном под фото в тёмной раме, над ней наклонённое кольцо поля на двух стойках,
    на кольце четыре фиолетовых узла."""
    _mats()
    c = (0.0, 0.2, 0.0)
    shell = sphere("HLR_Shell", 0.145, c, "Base_" + base, 32, 16)
    cut_box(shell, (0.0, 0.2, 0.16), (0.2, 0.16, 0.06))
    objs = [fin(shell, 0.0, angle=50.0, uv="cyl")]
    objs.append(rounded_frame("HLR_Frame", (0.0, 0.2), 0.092, 0.072, 0.009, "League_Void", 0.13))
    tilt = Rx(-18.0)
    ring_c = Vector((0.0, 0.3, -0.02))
    pts = [ring_c + tilt.to_3x3() @ Vector((0.2 * math.cos(2 * math.pi * k / 40), 0.0, 0.2 * math.sin(2 * math.pi * k / 40)))
           for k in range(40)]
    objs.append(fin(sweep("HLR_Halo", pts, 0.011, "League_Void", sides=8, closed=True), angle=60))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        p = ring_c + tilt.to_3x3() @ Vector((0.2 * math.cos(a), 0.0, 0.2 * math.sin(a)))
        objs.append(sphere("HLR_Node", 0.022, tuple(p), "League_Glow", 10, 5))
    for sx in (-1, 1):
        a0 = Vector((sx * 0.12, 0.26, -0.03))
        a1 = ring_c + tilt.to_3x3() @ Vector((sx * 0.2, 0.0, 0.0))
        objs.append(fin(sweep("HLR_Strut", [a0, a0.lerp(a1, 0.5) + Vector((sx * 0.02, 0.02, 0.0)), a1], 0.006, "League_Void", sides=6),
                        angle=60))
    objs += neck_stub("HLR")
    face = face_plate("FacePlate", (0.0, 0.2, 0.131), 0.17, 0.13, cols=10, rows=8, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.37, 0.0), 180.0), shape_sphere("Head", c, 0.15)]
    return objs, empties, [face]


# ---------------------------------------------------------------------------------------------------------------------------------
# ядра
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Core_LeagueOrb(base="Iron"):
    """Ядро-око: тёмный шар с огромным фиолетовым зрачком в золотой обойме, над ним кольцо-стабилизатор с голубыми узлами,
    пояс цвета игрока внизу, бобышки на якорях с голубыми кольцами."""
    _mats()
    R = 0.2
    objs = [fin(sphere("CLO_Ball", R, (0, 0, 0), "Base_" + base, 32, 16), angle=60.0, uv="cyl")]
    eye = align_y((0, 0, 1), (0.0, 0.0, 0.0))
    objs.append(fin(revolve("CLO_Bezel", [(0.105, 0.165), (0.112, 0.18), (0.1, 0.2), (0.078, 0.206), (0.07, 0.195)], "League_Gold", 36, eye,
                            closed=True), 0.002, 1, uv="cyl"))
    objs.append(revolve("CLO_Iris", [(0.08, 0.19), (0.06, 0.2), (0.03, 0.206), (0.0, 0.208)], "League_Glow", 32, eye))
    objs.append(fin(box("CLO_Pupil", (0.018, 0.075, 0.01), "League_Void", (0.0, 0.0, 0.21)), 0.004, 2))
    ry = 0.13
    rr = math.sqrt(R * R - ry * ry) + 0.024
    objs.append(fin(torus("CLO_Ring", (0.0, ry, 0.0), rr, 0.011, "League_Gold", 'XZ', 36, 8), angle=80))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        objs.append(sphere("CLO_RingNode", 0.016, (rr * math.cos(a), ry, rr * math.sin(a)), "League_Cyan", 8, 4))
    objs.append(_player_band("CLO_PlayerBand", -0.066, -0.153, lambda y: math.sqrt(max(R * R - y * y, 0.0)), lift=0.004, segs=32,
                             steps=3))
    bo, empties = _bosses("CLO", R, BALL_ANCHORS)
    objs += bo
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


def build_Core_LeagueGyro(base="Brass"):
    """Ядро-гироскоп: латунный шар с голубым светящимся швом, вокруг два карданных кольца (вертикальное и горизонтальное —
    спереди читаются крестом), пояс цвета игрока, тёмные бобышки на якорях."""
    _mats()
    R = 0.18
    objs = [fin(sphere("CLG_Ball", R, (0, 0, 0), "Base_" + base, 32, 16), angle=60.0, uv="cyl")]
    objs.append(torus("CLG_Seam", (0.0, 0.0, 0.0), R + 0.002, 0.006, "League_Cyan", 'XZ', 40, 6))
    objs.append(fin(torus("CLG_RingV", (0.0, 0.0, 0.0), 0.25, 0.013, "League_Gold", 'YZ', 44, 8), angle=80))
    objs.append(fin(torus("CLG_RingH", (0.0, 0.0, 0.0), 0.335, 0.013, "League_Gold", 'XZ', 52, 8), angle=80))
    for sz in (-1, 1):   # оси подвеса вертикального кольца
        objs.append(fin(revolve("CLG_Pivot", [(0.018, 0.0), (0.018, 0.07), (0.0, 0.075)], "League_Void", 12,
                                align_y((0, 0, sz), (0.0, 0.0, sz * (R - 0.01)))), 0.002, 1, uv="cyl"))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        objs.append(sphere("CLG_Node", 0.018, (0.335 * math.cos(a), 0.0, 0.335 * math.sin(a)), "League_Glow", 8, 4))
    objs.append(_player_band("CLG_PlayerBand", -0.05, -0.135, lambda y: math.sqrt(max(R * R - y * y, 0.0)), lift=0.004, segs=32,
                             steps=3))
    anchors = [("Neck", 90.0, 0.242), ("Shoulder_L", 44.0, 0.262), ("Shoulder_R", 136.0, 0.262), ("Side_L", -5.0, 0.242),
               ("Side_R", 185.0, 0.242), ("Hip_L", -62.0, 0.242), ("Hip_R", -118.0, 0.242)]
    bo, empties = _bosses("CLG", R, [(n, a, d + 0.02) for n, a, d in anchors])
    objs += bo
    empties.append(anchor("Back", (0.0, 0.12, -0.13), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# конечности (L, r, ja, jb — как у kit_limbs; размеры S / L даёт body_kit.sized)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Limb_LeagueCrystal(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Iron"):
    """Кристальная: шестигранный энергокристалл между тёмными обоймами, внутри голубая прожилка, полоска цвета игрока сверху."""
    _mats()
    ya, yb = ja * 0.6, L - jb * 0.6
    objs = ferrule("LLC_Top", -ya + 0.012, -ya - 0.034, r * 0.95, "Base_" + base, rivets=0)
    objs += ferrule("LLC_Bot", -yb + 0.03, -yb - 0.01, r * 0.88, "Base_" + base, rivets=0)
    y0, y1 = -ya - 0.03, -yb + 0.026
    rings = []
    for t, rad in ((0.0, r * 0.62), (0.12, r * 0.86), (0.55, r * 0.8), (0.88, r * 0.66), (1.0, r * 0.5)):
        y = y0 + (y1 - y0) * t
        rings.append([(rad * math.cos(2 * math.pi * i / 6 + 0.35 * t), y, rad * math.sin(2 * math.pi * i / 6 + 0.35 * t)) for i in range(6)])
    objs.append(fin(loft("LLC_Crystal", rings, "League_Crystal"), angle=20.0))
    objs.append(revolve("LLC_Vein", [(0.0, y0 - 0.005), (r * 0.16, y0 - 0.01), (r * 0.16, y1 + 0.01), (0.0, y1 + 0.005)], "League_Cyan", 8))
    objs.append(band("LLC_Stripe", -ya - 0.045, r * 0.98, 0.016, "Shirt_Kit"))
    return objs, limb_empties(L, r * 0.85)


def build_Limb_LeagueScythe(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Iron"):
    """Коса: тёмный сегмент в пустотных кольцах, по внешней стороне (+X) — изогнутое лезвие с фиолетовой кромкой, острие
    выходит за нижний шарнир; полоска цвета игрока сверху."""
    _mats()
    ya, yb = ja * 0.6, L - jb * 0.6
    objs = [peg("LLS_Body", -ya, -yb, r * 0.72, r * 0.62, "Base_" + base, bulge=0.04)]
    for i in range(3):
        y = -ya - (yb - ya) * (0.2 + 0.3 * i)
        objs.append(band("LLS_Ring", y, r * 0.8, 0.018, "League_Void"))
    # лезвие: полумесяц в плоскости XY (лицом к камере), от верхнего кольца наружу и вниз, острие ниже конца сегмента
    top, bot = -ya - 0.02, -L - r * 0.9
    outer, inner = [], []
    n = 16
    for k in range(n + 1):
        t = k / n
        y = top + (bot - top) * t
        bulge = math.sin(math.pi * min(t / 0.92, 1.0))
        outer.append((r * 0.55 + (r * 1.45 + 0.02) * bulge, y))
        inner.append((r * 0.55 + (r * 0.45) * bulge * 0.9, y))
    blade = outer + list(reversed(inner[1:-1]))
    objs.append(fin(extrude2d("LLS_Blade", blade, -0.006, 0.006, "League_Void"), 0.002, 1, angle=30.0))
    edge = [Vector((x, y, 0.0)) for x, y in outer]
    objs.append(sweep("LLS_Edge", edge, [0.0045] * len(edge), "League_Glow", sides=6))
    objs.append(band("LLS_Stripe", -ya - 0.035, r * 0.78, 0.016, "Shirt_Kit"))
    return objs, limb_empties(L, r * 0.75)


# ---------------------------------------------------------------------------------------------------------------------------------
# кисть
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Hand_LeagueTalon(base="Brass"):
    """Когти: пустотная манжета, латунная ладонь, три длинных золотых когтя-серпа с фиолетовыми остриями (средний — к камере),
    полоска цвета игрока."""
    _mats()
    objs = ferrule("HLT_Cuff", -0.012, -0.05, 0.046, "League_Void", rivets=3)
    objs.append(rbox("HLT_Palm", (0.088, 0.058, 0.066), "Base_" + base, (0.0, -0.077, 0.0), 0.02, 2))
    for sx in (-1, 0, 1):
        root = Vector((sx * 0.032, -0.1, 0.0 if sx else 0.012))
        if sx:
            ctrl = [root, root + Vector((sx * 0.05, -0.05, 0.0)), root + Vector((sx * 0.03, -0.12, 0.01)), root + Vector((-sx * 0.012, -0.15, 0.02))]
        else:
            ctrl = [root, root + Vector((0.0, -0.06, 0.02)), root + Vector((0.0, -0.12, 0.05)), root + Vector((0.0, -0.14, 0.085))]
        pts = []
        for i in range(10):   # кубическая Безье по четырём точкам
            t = i / 9
            a, b, c, d = ctrl
            pts.append(a * (1 - t) ** 3 + b * 3 * (1 - t) ** 2 * t + c * 3 * (1 - t) * t * t + d * t ** 3)
        radii = [0.013 * (1 - i / 9) ** 0.7 + 0.002 for i in range(10)]
        objs.append(fin(sweep("HLT_Talon", pts, radii, "League_Gold", sides=8), angle=60))
        objs.append(sphere("HLT_Tip", 0.006, tuple(pts[-1]), "League_Glow", 8, 4))
        objs.append(fin(sphere("HLT_Knuckle", 0.018, tuple(root), "League_Void", 12, 6), angle=80))
    objs.append(band("HLT_Stripe", -0.058, 0.05, 0.014, "Shirt_Kit"))
    return objs, [socket(), shape_box("Hand", (0.0, -0.12, 0.0), (0.12, 0.16, 0.07))]


# ---------------------------------------------------------------------------------------------------------------------------------
# навершия оружия (как kit_weapons: Socket в проушине, рукоять снизу, деталь растёт в −Y)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Blade_LeagueCrystal(base="Iron"):
    """Кристальный клинок: обойма с полоской цвета игрока, золотая гарда-полумесяц, узкий ромбический клинок из энергокристалла
    с голубой прожилкой по оси."""
    _mats()
    objs = _collar("BLC", -0.07, stripe=-0.05)
    objs.append(fin(revolve("BLC_Neck", [(0.0, -0.06), (0.032, -0.06), (0.034, -0.08), (0.026, -0.1), (0.0, -0.1)], "Base_" + base, 16),
                    0.002, 1, uv="cyl"))
    guard = [(-0.11, -0.085), (-0.06, -0.1), (0.0, -0.105), (0.06, -0.1), (0.11, -0.085), (0.1, -0.108), (0.05, -0.122), (0.0, -0.126),
             (-0.05, -0.122), (-0.1, -0.108)]
    objs.append(fin(extrude2d("BLC_Guard", guard, -0.018, 0.018, "League_Gold"), 0.003, 1, angle=40))

    def section(y, hw, t):
        return [(hw, y, 0.0), (0.0, y, t), (-hw, y, 0.0), (0.0, y, -t)]

    st = [(-0.11, 0.024, 0.012), (-0.2, 0.034, 0.012), (-0.4, 0.03, 0.01), (-0.56, 0.02, 0.008), (-0.63, 0.008, 0.004)]
    objs.append(fin(loft("BLC_Blade", [section(y, hw, t) for y, hw, t in st], "League_Crystal", pole1=(0.0, -0.68, 0.0)), angle=20.0))
    objs.append(revolve("BLC_Vein", [(0.0, -0.1), (0.005, -0.11), (0.005, -0.58), (0.0, -0.6)], "League_Cyan", 6))
    empties = [socket(), shape_box("Collar", (0.0, -0.04, 0.0), (0.072, 0.09, 0.072)),
               shape_box("Guard", (0.0, -0.105, 0.0), (0.22, 0.04, 0.04)), shape_box("Blade", (0.0, -0.39, 0.0), (0.07, 0.55, 0.03))]
    return objs, empties


def build_Mace_LeagueOrb(base="Iron"):
    """Шар-булава лиги: обойма, золотая шейка, тёмный шар с фиолетовым светящимся экватором и шестью кристальными шипами."""
    _mats()
    objs = _collar("MLO", -0.07, stripe=-0.05)
    objs.append(fin(revolve("MLO_Neck", [(0.0, -0.06), (0.03, -0.06), (0.03, -0.1), (0.022, -0.12), (0.0, -0.125)], "League_Gold", 16),
                    0.002, 1, uv="cyl"))
    c = Vector((0.0, -0.2, 0.0))
    R = 0.085
    objs.append(fin(sphere("MLO_Ball", R, tuple(c), "Base_" + base, 24, 12), angle=60.0, uv="cyl"))
    objs.append(torus("MLO_Equator", tuple(c), R + 0.003, 0.009, "League_Glow", 'XY', 32, 6))
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        d = Vector((math.cos(a), math.sin(a), 0.35 if k % 2 else -0.35)).normalized()   # шипы через один чуть к камере / от неё
        objs.append(fin(_shard("MLO_Spike", tuple(c + d * (R - 0.01)), tuple(d), 0.09, 0.018, "League_Crystal", sides=5, taper=0.4),
                        angle=20.0))
    empties = [socket(), shape_box("Collar", (0.0, -0.04, 0.0), (0.072, 0.09, 0.072)), shape_sphere("Ball", tuple(c), R + 0.03)]
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# декор и броня
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Deco_LeagueHalo(base="Iron"):
    """Гало поля (на макушку, Anchor_Top): короткая стойка, голубой шар-сенсор и парящее над ним кольцо с тремя фиолетовыми
    узлами на тонких спицах."""
    _mats()
    objs = [fin(revolve("DLH_Post", [(0.03, 0.0), (0.03, 0.015), (0.012, 0.03), (0.01, 0.1), (0.0, 0.105)], "Base_" + base, 14), 0.002, 1,
                uv="cyl")]
    objs.append(sphere("DLH_Orb", 0.026, (0.0, 0.115, 0.0), "League_Cyan", 12, 6))
    ring_y, ring_r = 0.15, 0.1
    objs.append(fin(torus("DLH_Ring", (0.0, ring_y, 0.0), ring_r, 0.008, "League_Void", 'XZ', 32, 6), angle=80))
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        p = Vector((ring_r * math.cos(a), ring_y, ring_r * math.sin(a)))
        objs.append(sphere("DLH_Node", 0.016, tuple(p), "League_Glow", 8, 4))
        objs.append(fin(sweep("DLH_Spoke", [Vector((0.0, 0.1, 0.0)), p], 0.003, "League_Void", sides=4), angle=60))
    return objs, [socket(rot_z=180.0), shape_cyl("Halo", (0.0, 0.09, 0.0), 0.11, 0.18)]


def build_Deco_LeagueShield(base="Iron", r=0.058):
    """Энергощит на конечность (Anchor_Deco): манжета цвета игрока, тёмный кронштейн, шестиугольная пластина энергокристалла
    перед конечностью в золотой раме; r — радиус конечности (0.058 рука, 0.074 нога)."""
    _mats()
    R = r * 1.25
    objs = [band("DLS_Cuff", -0.045, R, 0.022, "Shirt_Kit")]
    objs.append(fin(revolve("DLS_Collar", [(R * 0.98, -0.03), (R * 1.08, -0.035), (R * 1.08, -0.07), (R * 0.98, -0.075)], "Base_" + base, 22,
                            closed=True), 0.002, 1, uv="cyl"))
    zc = R + 0.03
    cy = -0.12 - r
    hx = [(math.cos(math.pi / 6 + k * math.pi / 3) * r * 1.9, cy + math.sin(math.pi / 6 + k * math.pi / 3) * r * 2.2) for k in range(6)]
    objs.append(fin(extrude2d("DLS_Plate", hx, zc, zc + 0.01, "League_Crystal", bend=2.0), angle=20.0))
    frame = [Vector((x, y, zc + 0.012 - 2.0 * x * x)) for x, y in hx]
    objs.append(fin(sweep("DLS_Frame", frame, 0.007, "League_Gold", sides=6, closed=True), angle=60))
    objs.append(fin(box("DLS_Bracket", (0.03, 0.05, zc - R + 0.01), "League_Void", (0.0, -0.075, (R + zc) / 2)), 0.003, 1))
    objs.append(sphere("DLS_Emitter", 0.012, (0.0, cy, zc + 0.016), "League_Glow", 8, 4))
    return objs, [socket(), shape_box("Shield", (0.0, cy, zc), (r * 3.6, r * 4.2, 0.03))]


META = {
    "Head_LeagueEye": {"kind": "head", "title": "Голова-око (лига)", "mass": 4.2, "energy": 10},
    "Head_LeagueCrystal": {"kind": "head", "title": "Кристальная голова (лига)", "mass": 5.0, "energy": 11},
    "Head_LeagueRing": {"kind": "head", "title": "Голова с гало (лига)", "mass": 4.4, "energy": 10},
    "Core_LeagueOrb": {"kind": "core", "title": "Ядро-око (лига)", "mass": 14.0, "energy": 0},
    "Core_LeagueGyro": {"kind": "core", "title": "Ядро-гироскоп (лига)", "mass": 15.0, "energy": 0},
    "Limb_LeagueCrystal": {"kind": "limb", "title": "Кристальная (лига)", "mass": {"S": 1.8, "L": 3.6}, "energy": {"S": 6, "L": 8}},
    "Limb_LeagueScythe": {"kind": "limb", "title": "Коса (лига)", "mass": {"S": 2.4, "L": 4.6}, "energy": {"S": 7, "L": 9}},
    "Hand_LeagueTalon": {"kind": "hand", "title": "Когти (лига)", "mass": 1.0, "energy": 4},
    "Blade_LeagueCrystal": {"kind": "weapon_head", "title": "Кристальный клинок (лига)", "mass": 1.1, "energy": 0, "weapon_mult": 1.5,
                            "name_prefix": "Blade"},
    "Mace_LeagueOrb": {"kind": "weapon_head", "title": "Шар-булава (лига)", "mass": 2.6, "energy": 0, "weapon_mult": 1.4,
                       "name_prefix": "Mace"},
    "Deco_LeagueHalo": {"kind": "deco", "title": "Гало поля (лига)", "mass": 0.4, "energy": 2},
    "Deco_LeagueShield": {"kind": "armor", "title": "Энергощит (лига)", "mass": {"S": 0.9, "L": 1.4}, "energy": 4},
}
