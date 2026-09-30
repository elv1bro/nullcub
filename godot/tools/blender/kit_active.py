"""Активные блоки кита (docs/plan-demo/ACTIVE_BLOCKS.md): детали с действием на клавише канала 1–3 — пока клавиша зажата, блок
работает и тратит заряд. Действия, цены и силы — scripts/active/active_blocks.gd (ActiveBlocks.DEFS, по id детали); здесь — только
модели. Вид детали — deco (как декор: без своего тела, сливается с конечностью или ядром; якоря Deco / Back / Top).

Ось действия — +Y детали. Сокет повёрнут на 180° (как у декора спины и макушки), поэтому:
  • на конечности (Anchor_Deco) +Y смотрит вдоль конечности к кисти / стопе — целишься рукой, как оружием;
  • на спине (Anchor_Back) и макушке (Anchor_Top) +Y смотрит вверх.
Блоки для конечности сидят спереди (+Z, к камере), блоки для спины и макушки — сзади и над плечами (Z ≤ 0).

Кит — игрушечный стиль (железо, латунь, краска, Base_<Mat> — корпус на оси материалов); модули лиги — язык kit_league.py
(пустотный металл, свет поля, Base_ — латунная отделка).
"""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
from kit_league import _mats as _league_mats, _shard

Z_LIMB = 0.085   # центр блока перед конечностью (радиус руки 0.058 + зазор)


def _strap(prefix, y, r=0.066):
    """Хомут крепления к конечности: железная полоса вокруг руки у сокета (в кадре сзади блока) + латунная пряжка."""
    return [band(prefix + "_Strap", y, r, 0.022, "Iron"),
            fin(rbox(prefix + "_Buckle", (0.034, 0.03, 0.02), "Brass", (0.0, y, r + 0.006), 0.004, 1), angle=40)]


def _can(name, y0, y1, r, mat, z=Z_LIMB, x=0.0, segs=18):
    """Цилиндр-баллон вдоль +Y со скруглёнными торцами."""
    prof = [(0.0, y0), (r * 0.7, y0), (r, y0 + 0.012), (r, y1 - 0.012), (r * 0.7, y1), (0.0, y1)]
    return fin(revolve(name, prof, mat, segs, T((x, 0.0, z))), 0.0, angle=40.0, uv="cyl")


# ---------------------------------------------------------------------------------------------------------------------------------
# кит: конечность (спереди, +Y — к кисти)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Active_Booster(base="PaintRed"):
    """Ускоритель: крашеный баллон-ракета перед конечностью, железное сопло к плечу (выхлоп назад), тянет конечность к кисти;
    жёлто-чёрные полосы опасности, латунный носовой колпак, хомут."""
    objs = _strap("AB", 0.02)
    objs.append(_can("AB_Body", 0.04, 0.2, 0.034, "Base_" + base))
    objs.append(fin(revolve("AB_Nose", [(0.03, 0.2), (0.026, 0.215), (0.012, 0.232), (0.0, 0.236)], "Brass", 16, T((0.0, 0.0, Z_LIMB))),
                    0.0, angle=40, uv="cyl"))
    objs.append(fin(revolve("AB_Nozzle", [(0.02, 0.04), (0.024, 0.03), (0.036, 0.0), (0.038, -0.006), (0.03, -0.006), (0.02, 0.02)],
                            "Iron", 16, T((0.0, 0.0, Z_LIMB)), closed=True), 0.0, angle=40, uv="cyl"))
    objs.append(revolve("AB_Glow", [(0.0, 0.004), (0.02, 0.004), (0.0, 0.03)], "CoreGlow", 12, T((0.0, 0.0, Z_LIMB))))
    for y in (0.09, 0.14):
        objs.append(band("AB_Hazard", y, 0.0355, 0.014, "Bone"))
    for sx in (-1, 1):   # стабилизаторы
        fin_pts = [(0.0, 0.0), (0.03, -0.02), (0.03, 0.03), (0.0, 0.06)]
        objs.append(fin(extrude2d("AB_Fin", [(sx * (0.032 + x), 0.05 + y) for x, y in fin_pts] if sx > 0 else
                                  [(sx * (0.032 + x), 0.05 + y) for x, y in reversed(fin_pts)], Z_LIMB - 0.003, Z_LIMB + 0.003, "Iron"),
                        0.001, 1, angle=30))
    return objs, [socket(rot_z=180.0), shape_cyl("Booster", (0.0, 0.11, Z_LIMB), 0.04, 0.24)]


def build_Active_Flamer(base="PaintRed"):
    """Огнемёт: крашеный газовый баллон, железная труба с вентилем к соплу-раструбу у кисти, огонёк запальника."""
    objs = _strap("AF", 0.02)
    objs.append(_can("AF_Tank", 0.03, 0.15, 0.036, "Base_" + base))
    objs.append(fin(revolve("AF_Valve", [(0.0, 0.15), (0.012, 0.15), (0.012, 0.17), (0.0, 0.17)], "Brass", 10, T((0.0, 0.0, Z_LIMB))),
                    0.0, angle=40, uv="cyl"))
    objs.append(fin(sweep("AF_Pipe", [Vector((0.0, 0.165, Z_LIMB)), Vector((0.0, 0.2, Z_LIMB + 0.004)), Vector((0.0, 0.25, Z_LIMB + 0.01))],
                          0.009, "Iron", sides=8), angle=50))
    objs.append(fin(revolve("AF_Muzzle", [(0.011, 0.245), (0.016, 0.255), (0.024, 0.285), (0.02, 0.286), (0.012, 0.26)], "Rust", 14,
                            T((0.0, 0.0, Z_LIMB + 0.01)), closed=True), 0.0, angle=40, uv="cyl"))
    objs.append(sphere("AF_Pilot", 0.007, (0.0, 0.288, Z_LIMB + 0.028), "CoreGlow", 8, 4))
    objs.append(fin(torus("AF_Wheel", (0.022, 0.16, Z_LIMB), 0.014, 0.003, "Brass", 'YZ', 12, 4), angle=60))
    objs.append(band("AF_Stripe", 0.09, 0.0375, 0.016, "Bone"))
    return objs, [socket(rot_z=180.0), shape_cyl("Flamer", (0.0, 0.14, Z_LIMB), 0.04, 0.28)]


def build_Active_Gun(base="Iron"):
    """Пулемёт: вращающийся блок из четырёх стволов вдоль конечности (дульный срез у кисти), корпус-затвор, барабанный магазин
    сбоку, латунные патроны в ленте."""
    objs = _strap("AG", 0.02)
    objs.append(fin(rbox("AG_Receiver", (0.06, 0.08, 0.05), "Base_" + base, (0.0, 0.07, Z_LIMB), 0.008, 2), angle=40))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        x, z = 0.013 * math.cos(a), Z_LIMB + 0.013 * math.sin(a)
        objs.append(fin(revolve("AG_Barrel", [(0.0, 0.11), (0.0065, 0.11), (0.0065, 0.28), (0.0045, 0.28), (0.0045, 0.27), (0.0, 0.27)],
                                "Steel", 8, T((x, 0.0, z))), 0.0, angle=40, uv="cyl"))
    for y in (0.14, 0.26):
        objs.append(fin(revolve("AG_Clamp", [(0.024, y - 0.006), (0.025, y), (0.024, y + 0.006)], "Iron", 14, T((0.0, 0.0, Z_LIMB)),
                                closed=True), angle=60))
    drum_c = Vector((0.052, 0.07, Z_LIMB))
    objs.append(fin(revolve("AG_Drum", [(0.0, -0.018), (0.034, -0.018), (0.038, -0.012), (0.038, 0.012), (0.034, 0.018), (0.0, 0.018)],
                            "Base_" + base, 18, T(drum_c) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')), 0.0, angle=40, uv="cyl"))
    objs.append(fin(torus("AG_DrumRim", tuple(drum_c + Vector((0.0, 0.0, 0.0))), 0.036, 0.004, "Brass", 'XY', 18, 4), angle=60))
    for k in range(5):   # лента патронов из барабана в затвор
        p = Vector((0.03 - k * 0.006, 0.045 - k * 0.004, Z_LIMB + 0.02))
        objs.append(fin(revolve("AG_Round", [(0.0, 0.0), (0.004, 0.0), (0.004, 0.012), (0.0, 0.018)], "Brass", 8,
                                align_y((1.0, -0.2, 0.0), p)), angle=50))
    return objs, [socket(rot_z=180.0), shape_box("Gun", (0.02, 0.15, Z_LIMB), (0.12, 0.28, 0.06))]


def build_Active_Magnet(base="PaintRed"):
    """Магнит: крашеная подкова на кронштейне, железные полюса смотрят к кисти (+Y), катушка из медной проволоки на перемычке —
    тянет детали из железа (MaterialDef.iron)."""
    objs = _strap("AM", 0.02)
    objs.append(fin(box("AM_Bracket", (0.02, 0.06, 0.03), "Iron", (0.0, 0.05, Z_LIMB - 0.01)), 0.003, 1))
    pts = [Vector((0.045 * math.cos(math.pi + math.pi * k / 12), 0.12 + 0.045 * math.sin(math.pi + math.pi * k / 12) * -1.0, Z_LIMB))
           for k in range(13)]
    shoe = [Vector((-0.045, 0.2, Z_LIMB))] + [Vector((p.x, 0.12 - (p.y - 0.12), p.z)) for p in pts] + [Vector((0.045, 0.2, Z_LIMB))]
    objs.append(fin(sweep("AM_Shoe", shoe, 0.016, "Base_" + base, sides=8), angle=50))
    for sx in (-1, 1):
        objs.append(fin(box("AM_Pole", (0.034, 0.03, 0.034), "Steel", (sx * 0.045, 0.21, Z_LIMB)), 0.003, 1))
    for k in range(6):
        objs.append(fin(torus("AM_Coil", (0.0, 0.066 + k * 0.006, Z_LIMB), 0.02, 0.0035, "Brass", 'XZ', 12, 4), angle=60))
    return objs, [socket(rot_z=180.0), shape_box("Magnet", (0.0, 0.14, Z_LIMB), (0.12, 0.16, 0.04))]


# ---------------------------------------------------------------------------------------------------------------------------------
# кит: спина (Anchor_Back, +Y — вверх, Z ≤ 0 — за спиной)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Active_Jetpack(base="PaintYellow"):
    """Реактивный ранец: два крашеных баллона по бокам за плечами на железной раме, сопла вниз (выхлоп вниз — тянет вверх),
    ремни цвета игрока, латунные манометры."""
    objs = [fin(rbox("AJ_Frame", (0.22, 0.05, 0.03), "Iron", (0.0, 0.0, -0.02), 0.008, 2), angle=40)]
    for sx in (-1, 1):
        x = sx * 0.17
        objs.append(_can("AJ_Tank", -0.14, 0.12, 0.05, "Base_" + base, z=-0.05, x=x))
        objs.append(fin(revolve("AJ_Cap", [(0.045, 0.12), (0.03, 0.14), (0.0, 0.146)], "Brass", 16, T((x, 0.0, -0.05))), 0.0, angle=40,
                        uv="cyl"))
        objs.append(fin(revolve("AJ_Nozzle", [(0.03, -0.14), (0.034, -0.16), (0.05, -0.2), (0.046, -0.204), (0.03, -0.17)], "Iron", 16,
                                T((x, 0.0, -0.05)), closed=True), 0.0, angle=40, uv="cyl"))
        objs.append(revolve("AJ_Glow", [(0.0, -0.15), (0.034, -0.196), (0.0, -0.19)], "CoreGlow", 12, T((x, 0.0, -0.05))))
        objs.append(band("AJ_Strap", -0.02, 0.052, 0.02, "Shirt_Kit") if False else
                    fin(revolve("AJ_Strap", [(0.052, -0.03), (0.053, -0.02), (0.052, -0.01)], "Shirt_Kit", 16, T((x, 0.0, -0.05)), closed=True),
                        angle=60))
        objs.append(fin(sphere("AJ_Gauge", 0.016, (x - sx * 0.035, 0.07, -0.012), "Brass", 10, 5), angle=60))
    return objs, [socket(rot_z=180.0), shape_box("Jetpack", (0.0, -0.01, -0.05), (0.46, 0.3, 0.1))]


# ---------------------------------------------------------------------------------------------------------------------------------
# лига: модули (язык kit_league.py)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Active_LeagueGravity(base="Brass"):
    """Гравиядро лиги (спина / макушка): чёрная сфера с фиолетовым светящимся поясом над плечами, вокруг — два наклонённых
    кольца поля, латунная стойка (Base_)."""
    _league_mats()
    c = Vector((0.0, 0.22, -0.05))
    objs = [fin(revolve("ALG_Post", [(0.028, 0.0), (0.028, 0.02), (0.012, 0.04), (0.012, 0.15), (0.0, 0.16)], "Base_" + base, 12,
                        T((0.0, 0.0, -0.05))), 0.002, 1, uv="cyl")]
    objs.append(fin(sphere("ALG_Orb", 0.07, tuple(c), "League_Void", 20, 10), angle=60))
    objs.append(torus("ALG_Belt", tuple(c), 0.071, 0.008, "League_Glow", 'XZ', 28, 5))
    for tilt in (25.0, -25.0):
        xf = T(c) @ Rx(tilt) @ Rz(tilt * 0.6)
        pts = [xf @ Vector((0.12 * math.cos(2 * math.pi * k / 28), 0.0, 0.12 * math.sin(2 * math.pi * k / 28))) for k in range(28)]
        objs.append(sweep("ALG_Ring", pts, 0.004, "League_Glow", sides=5, closed=True))
    objs.append(sphere("ALG_Core", 0.02, tuple(c + Vector((0.0, 0.0, 0.066))), "League_Cyan", 10, 5))
    return objs, [socket(rot_z=180.0), shape_sphere("Gravity", tuple(c), 0.08)]


def build_Active_LeagueShield(base="Brass"):
    """Эмиттер энергощита (конечность, спереди): латунный хомут (Base_), чёрная линза в кольце поля и три кристальных лепестка —
    пока канал зажат, вокруг бойца купол, урон по нему гасится."""
    _league_mats()
    objs = [band("ALS_Strap", 0.02, 0.066, 0.024, "Base_" + base)]
    c = Vector((0.0, 0.1, Z_LIMB))
    objs.append(fin(revolve("ALS_Lens", [(0.0, -0.012), (0.034, -0.012), (0.04, 0.0), (0.03, 0.012), (0.0, 0.016)], "League_Void", 20,
                            T(c) @ Rx(90.0)), 0.0, angle=50, uv="cyl"))
    objs.append(torus("ALS_Ring", tuple(c + Vector((0.0, 0.0, 0.012))), 0.042, 0.004, "League_Glow", 'XY', 28, 5))
    objs.append(sphere("ALS_Eye", 0.014, tuple(c + Vector((0.0, 0.0, 0.016))), "League_Cyan", 10, 5))
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        d = Vector((math.cos(a), math.sin(a), 0.25)).normalized()
        objs.append(fin(_shard("ALS_Petal", tuple(c + d * 0.04), tuple(d), 0.06, 0.014, "League_Crystal", sides=5, taper=0.5), angle=20))
    objs.append(fin(box("ALS_Stem", (0.02, 0.06, 0.03), "League_Void", (0.0, 0.05, Z_LIMB - 0.02)), 0.004, 1))
    return objs, [socket(rot_z=180.0), shape_cyl("Shield", tuple(c), 0.06, 0.03)]


def build_Active_LeaguePhase(base="Brass"):
    """Фазовый модуль лиги (спина / макушка): вертикальная голубая призма фазового стекла в трёх парящих латунных (Base_)
    кольцах, внутри светится фиолетовая нить — пока канал зажат, боец проходит сквозь чужие тела."""
    _league_mats()
    c = Vector((0.0, 0.2, -0.05))
    objs = [fin(revolve("ALP_Post", [(0.026, 0.0), (0.026, 0.02), (0.01, 0.04), (0.01, 0.1), (0.0, 0.11)], "League_Void", 10,
                        T((0.0, 0.0, -0.05))), 0.002, 1, uv="cyl")]
    objs.append(fin(_shard("ALP_Prism", tuple(c - Vector((0.0, 0.1, 0.0))), (0.0, 1.0, 0.0), 0.24, 0.04, "League_Crystal", sides=6, taper=0.9),
                    angle=20))
    objs.append(revolve("ALP_Thread", [(0.0, 0.1), (0.006, 0.12), (0.006, 0.3), (0.0, 0.32)], "League_Glow", 6, T((0.0, 0.0, -0.05))))
    for k, y in enumerate((0.13, 0.2, 0.27)):
        objs.append(fin(torus("ALP_Ring", (0.0, y, -0.05), 0.055 - k * 0.006, 0.005, "Base_" + base, 'XZ', 24, 5), angle=60))
    return objs, [socket(rot_z=180.0), shape_cyl("Phase", tuple(c), 0.05, 0.26)]


def build_Active_LeagueRepair(base="Brass"):
    """Ядро самопочинки лиги (спина / макушка): чёрная капсула с голубым окном, в окне — светящийся знак «+» из кристалла, латунные
    зажимы (Base_) — пока канал зажат, заряд идёт в здоровье."""
    _league_mats()
    c = Vector((0.0, 0.16, -0.05))
    objs = [fin(revolve("ALR_Body", [(0.0, 0.04), (0.04, 0.045), (0.05, 0.08), (0.05, 0.24), (0.04, 0.275), (0.0, 0.28)], "League_Void", 20,
                        T((0.0, 0.0, -0.05))), 0.0, angle=50, uv="cyl")]
    objs.append(fin(box("ALR_Window", (0.06, 0.12, 0.012), "League_Cyan", (0.0, 0.16, -0.002)), 0.003, 1))
    for w, h in ((0.012, 0.07), (0.05, 0.012)):
        objs.append(fin(box("ALR_Cross", (w, h, 0.01), "League_Crystal", (0.0, 0.16, 0.006)), 0.002, 1))
    for y in (0.07, 0.25):
        objs.append(fin(revolve("ALR_Clamp", [(0.051, y - 0.01), (0.056, y), (0.051, y + 0.01)], "Base_" + base, 20, T((0.0, 0.0, -0.05)),
                                closed=True), angle=60))
    return objs, [socket(rot_z=180.0), shape_cyl("Repair", tuple(c), 0.055, 0.24)]


META = {
    "Active_Booster": {"kind": "deco", "title": "Ускоритель", "mass": 1.0, "energy": 5},
    "Active_Flamer": {"kind": "deco", "title": "Огнемёт", "mass": 1.4, "energy": 7},
    "Active_Gun": {"kind": "deco", "title": "Пулемёт", "mass": 1.6, "energy": 8},
    "Active_Magnet": {"kind": "deco", "title": "Магнит", "mass": 1.2, "energy": 5},
    "Active_Jetpack": {"kind": "deco", "title": "Реактивный ранец", "mass": 2.0, "energy": 8},
    "Active_LeagueGravity": {"kind": "deco", "title": "Гравиядро (лига)", "mass": 1.5, "energy": 9},
    "Active_LeagueShield": {"kind": "deco", "title": "Эмиттер щита (лига)", "mass": 1.0, "energy": 8},
    "Active_LeaguePhase": {"kind": "deco", "title": "Фазовый модуль (лига)", "mass": 0.8, "energy": 9},
    "Active_LeagueRepair": {"kind": "deco", "title": "Ядро самопочинки (лига)", "mass": 1.0, "energy": 8},
}
