"""Модули кита (пассивные): детали без клавиши — работают всегда, пока стоят на теле (сервопривод, батарея, парус-щит, маховик,
пружина-отбойник, обтекатель, амортизатор сустава, ремкомплект, наждак). Действие модулей — в коде игры (по id детали); здесь —
только модели. Вид детали — deco, как у активных блоков (kit_active.py): без своего тела, сливается с конечностью, ядром или
головой; якоря Deco / Back / Top.

Оси — как в kit_active: сокет повёрнут на 180° (как у декора спины и макушки), поэтому
  • на конечности (Anchor_Deco) +Y смотрит вдоль конечности к кисти / стопе, модуль сидит спереди (+Z, к камере; Z_LIMB);
  • на спине (Anchor_Back) и макушке (Anchor_Top) +Y смотрит вверх, модуль — сзади (Z ≤ 0) и над плечами.
Модули конечности не длиннее y ≈ 0.235 от сокета: столько остаётся на предплечье (0.27) до кисти.

Язык модулей — чтобы на бойце не путать с активными блоками (баллоны, стволы, сопла на хомуте): механика на виду — шестерня,
пружины, маховик, гнутые листы на болтах; механизмы на конечности (сервопривод, отбойник, амортизатор) стоят на железном седле с
латунными болтами (_saddle), а не только на хомуте. Кит — игрушечный стиль (железо, латунь, краска, Base_<Mat> — корпус на оси материалов, BODY_KIT.md).
"""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
from kit_active import Z_LIMB, _can, _strap


def _lin(a, b, n):
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def _shell(name, y0, y1, r0, r1, half, mat, n=10):
    """Гнутый лист вокруг оси конечности (спереди, угол от +Z): дуга r1 и обратно дугой r0 на ±half рад, от y0 до y1."""
    rings = []
    for y in (y0, y1):
        ring = [(r1 * math.sin(a), y, r1 * math.cos(a)) for a in _lin(-half, half, n)]
        ring += [(r0 * math.sin(a), y, r0 * math.cos(a)) for a in _lin(half, -half, n)]
        rings.append(ring)
    return loft(name, rings, mat)


def _saddle(prefix, y0, y1, ang=55.0, r0=0.06, r1=0.067):
    """Седло модуля конечности: железная накладка по передней стороне конечности, четыре латунных болта по углам."""
    half = math.radians(ang)
    objs = [fin(_shell(prefix + "_Saddle", y0, y1, r0, r1, half, "Iron", 9), 0.0015, 1, angle=50)]
    for y in (y0 + 0.009, y1 - 0.009):
        for s in (-1, 1):
            a = s * (half - math.radians(10.0))
            nrm = Vector((math.sin(a), 0.0, math.cos(a)))
            objs.append(fin(stud(prefix + "_Bolt", Vector((0.0, y, 0.0)) + nrm * r1, nrm, "Brass", 0.0062, 0.0042, 6)))
    return objs


def _coil(name, y0, y1, r0, r1, turns, wire, mat, x=0.0, z=Z_LIMB, per_turn=12, sides=6):
    """Витая пружина вдоль +Y: радиус витка от r0 (y0) до r1 (y1) — конус или цилиндр."""
    n = int(turns * per_turn)
    pts = []
    for i in range(n + 1):
        t = i / n
        a = TAU * turns * t
        r = r0 + (r1 - r0) * t
        pts.append(Vector((x + r * math.cos(a), y0 + (y1 - y0) * t, z + r * math.sin(a))))
    return fin(sweep(name, pts, wire, mat, sides=sides), angle=60)


def _disc_z(name, prof, mat, center, segs=20):
    """Тело вращения вокруг оси Z (лицом к камере): prof [(r, z)], z — от центра."""
    return revolve(name, prof, mat, segs, T(center) @ Rx(90.0))


def _gear_pts(r_root, r_tip, teeth, cx=0.0, cy=0.0):
    pts = []
    da = TAU / teeth
    for k in range(teeth):
        for f, r in ((0.0, r_root), (0.16, r_tip), (0.48, r_tip), (0.64, r_root)):
            a = da * (k + f)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------------------------------------------------------------------------
# конечность (спереди, +Y — к кисти / стопе)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Mod_Servo(base="PaintBlue"):
    """Сервопривод: крашеный мотор с рёбрами вдоль конечности, над ним — круглый железный редуктор лицом к камере с латунной
    шестернёй; кривошип и короткая стальная тяга к хомуту у кисти — мотор помогает суставу."""
    objs = _strap("MSV", 0.02)
    objs += _saddle("MSV", 0.035, 0.2)
    z = Z_LIMB
    objs.append(_can("MSV_Motor", 0.03, 0.108, 0.029, "Base_" + base))
    for y in (0.055, 0.069, 0.083):   # рёбра охлаждения
        objs.append(fin(revolve("MSV_Rib", [(0.028, y - 0.004), (0.033, y - 0.0025), (0.033, y + 0.0025), (0.028, y + 0.004)], "Iron", 18,
                                T((0.0, 0.0, z)), closed=True), angle=60))
    objs.append(fin(revolve("MSV_Bearing", [(0.0, 0.022), (0.011, 0.022), (0.013, 0.032), (0.0, 0.032)], "Brass", 12, T((0.0, 0.0, z))),
                    angle=50))
    objs.append(fin(rbox("MSV_TermBox", (0.018, 0.024, 0.02), "Iron", (0.03, 0.045, z), 0.003, 1), angle=40))
    for dy in (-0.006, 0.006):
        objs.append(fin(stud("MSV_Term", (0.039, 0.045 + dy, z), (1.0, 0.0, 0.0), "Brass", 0.0042, 0.004, 6)))
    # редуктор: диск лицом к камере, шестерня, ступица, болты
    c = Vector((0.0, 0.138, z - 0.004))
    objs.append(fin(_disc_z("MSV_Gearbox", [(0.0, -0.016), (0.038, -0.016), (0.043, -0.011), (0.043, 0.011), (0.039, 0.016),
                                            (0.0, 0.016)], "Iron", c, 24), 0.0, angle=40, uv="cyl"))
    zf = c.z + 0.016
    objs.append(fin(extrude2d("MSV_Gear", _gear_pts(0.029, 0.036, 12, 0.0, c.y), zf - 0.002, zf + 0.007, "Brass"), 0.0, angle=30))
    objs.append(fin(_disc_z("MSV_Hub", [(0.0, 0.0), (0.012, 0.0), (0.012, 0.008), (0.009, 0.011), (0.0, 0.011)], "Iron",
                            (0.0, c.y, zf + 0.006), 14), angle=50))
    for k in range(4):
        a = TAU * k / 4 + math.pi / 4
        objs.append(fin(stud("MSV_GearBolt", (0.02 * math.cos(a), c.y + 0.02 * math.sin(a), zf + 0.007), (0.0, 0.0, 1.0), "Iron",
                             0.0045, 0.003, 6)))
    # кривошип и тяга к нижнему хомуту
    pin = Vector((0.0, c.y + 0.026, zf + 0.016))
    objs.append(fin(rbox("MSV_Crank", (0.014, 0.036, 0.006), "Iron", (0.0, c.y + 0.013, zf + 0.014), 0.003, 1), angle=40))
    objs.append(fin(sphere("MSV_Pin", 0.0065, tuple(pin), "Brass", 10, 5), angle=60))
    low = Vector((0.0, 0.212, z - 0.003))
    objs.append(fin(sweep("MSV_Rod", [pin, pin.lerp(low, 0.5) + Vector((0.0, 0.0, 0.004)), low], 0.0055, "Steel", sides=8), angle=50))
    objs.append(fin(sphere("MSV_RodEnd", 0.008, tuple(low), "Brass", 10, 5), angle=60))
    objs.append(band("MSV_Clamp", 0.215, 0.062, 0.016, "Iron"))
    objs.append(fin(rbox("MSV_Clevis", (0.024, 0.02, 0.022), "Iron", (0.0, 0.214, 0.072), 0.003, 1), angle=40))
    return objs, [socket(rot_z=180.0), shape_box("Servo", (0.0, 0.12, Z_LIMB), (0.09, 0.2, 0.05))]


# контур паруса-щита: (y, полуширина) от петли до острия
_SAIL = [(0.05, 0.11), (0.065, 0.128), (0.09, 0.134), (0.12, 0.126), (0.15, 0.106), (0.18, 0.078), (0.205, 0.048), (0.222, 0.022),
         (0.234, 0.004)]
_SAIL_ZF, _SAIL_T, _SAIL_BEND = 0.1, 0.006, 1.2


def _sail_z(x, lift=0.0):
    return _SAIL_ZF - _SAIL_BEND * x * x + lift


def build_Mod_Sail(base="RustRed"):
    """Парус-щит: широкий крашеный лист-«воздушный тормоз» перед конечностью (шире наплечника, как кайт-щит) висит на поперечной
    петле у хомута; железная кромка, хребет и две рейки, латунные заклёпки. Броня и сопротивление воздуха."""
    objs = _strap("MSL", 0.02)
    objs.append(fin(rbox("MSL_Bracket", (0.05, 0.03, 0.03), "Iron", (0.0, 0.03, 0.074), 0.004, 1), angle=40))
    # петля: пять звеньев вдоль X (железо / латунь через одно), ось — на верхней кромке листа
    hz, hy = 0.093, 0.042
    for k in range(5):
        x0 = -0.07 + k * 0.028
        objs.append(fin(revolve("MSL_Knuckle", [(0.0, x0 + 0.001), (0.0105, x0 + 0.001), (0.0115, x0 + 0.004), (0.0115, x0 + 0.024),
                                                (0.0105, x0 + 0.027), (0.0, x0 + 0.027)], "Brass" if k % 2 else "Iron", 12,
                                T((0.0, hy, hz)) @ Rz(-90.0)), 0.0, angle=40, uv="cyl"))
    # лист: лофт сечений (лицевая сторона z = ZF − bend·x², толщина T)
    rings = []
    for y, w in _SAIL:
        ring = [(x, y, _sail_z(x)) for x in _lin(-w, w, 9)]
        ring += [(x, y, _sail_z(x, -_SAIL_T)) for x in _lin(w, -w, 9)]
        rings.append(ring)
    objs.append(fin(loft("MSL_Sheet", rings, "Base_" + base), 0.0015, 1, angle=50))
    rim = [Vector((-w, y, _sail_z(w, -0.002))) for y, w in _SAIL] + [Vector((w, y, _sail_z(w, -0.002))) for y, w in reversed(_SAIL)]
    objs.append(fin(sweep("MSL_Rim", rim, 0.0048, "Iron", sides=6, closed=True), angle=60))
    objs.append(fin(sweep("MSL_Spine", [Vector((0.0, y, _sail_z(0.0, 0.002))) for y in _lin(0.055, 0.224, 5)], 0.0055, "Iron", sides=6),
                    angle=50))
    for yb in (0.1, 0.16):   # рейки паруса
        w = next(w0 + (w1 - w0) * (yb - y0) / (y1 - y0) for (y0, w0), (y1, w1) in zip(_SAIL, _SAIL[1:]) if y0 <= yb <= y1) - 0.012
        objs.append(fin(sweep("MSL_Batten", [Vector((x, yb, _sail_z(x, 0.0015))) for x in _lin(-w, w, 9)], 0.0035, "Iron", sides=5),
                        angle=60))
    for y, w in _SAIL[1:-2]:   # заклёпки вдоль кромки
        for s in (-1, 1):
            x = s * (w - 0.013)
            objs.append(fin(stud("MSL_Rivet", (x, y, _sail_z(x)), (2.0 * _SAIL_BEND * x, 0.0, 1.0), "Brass", 0.0055, 0.0036, 6)))
    return objs, [socket(rot_z=180.0), shape_box("Sail", (0.0, 0.14, 0.088), (0.27, 0.2, 0.05))]


def build_Mod_Bumper(base="PaintRed"):
    """Пружина-отбойник: короткая толстая крашеная пружина-конус вдоль конечности на железной стойке, на конце — чёрная резиновая
    шляпка-буфер на стальном диске (+Y, к кисти / стопе): смягчает и отбивает удары."""
    z = 0.092
    objs = _strap("MBU", 0.02)
    objs += _saddle("MBU", 0.035, 0.115)
    objs.append(fin(rbox("MBU_Post", (0.05, 0.04, 0.03), "Iron", (0.0, 0.07, 0.074), 0.004, 1), angle=40))
    objs.append(fin(revolve("MBU_Seat", [(0.0, 0.058), (0.033, 0.058), (0.038, 0.064), (0.038, 0.074), (0.03, 0.08), (0.0, 0.08)], "Iron",
                            20, T((0.0, 0.0, z))), 0.0, angle=40, uv="cyl"))
    objs.append(_coil("MBU_Coil", 0.08, 0.17, 0.031, 0.024, 4.0, 0.0068, "Base_" + base, z=z))
    objs.append(fin(revolve("MBU_Rod", [(0.0, 0.075), (0.008, 0.075), (0.008, 0.172), (0.0, 0.172)], "Steel", 8, T((0.0, 0.0, z))), angle=50))
    objs.append(fin(revolve("MBU_Plate", [(0.0, 0.166), (0.031, 0.166), (0.034, 0.171), (0.032, 0.177), (0.0, 0.177)], "Steel", 20,
                            T((0.0, 0.0, z))), 0.0, angle=40, uv="cyl"))
    objs.append(fin(revolve("MBU_Pad", [(0.0, 0.175), (0.04, 0.175), (0.045, 0.182), (0.044, 0.196), (0.036, 0.208), (0.02, 0.215),
                                        (0.0, 0.217)], "Rubber", 22, T((0.0, 0.0, z))), 0.0, angle=50, uv="cyl"))
    for k in range(3):   # шляпки болтов буфера
        a = TAU * k / 3 + math.pi / 2
        objs.append(fin(stud("MBU_Bolt", (0.024 * math.cos(a), 0.168, z + 0.024 * math.sin(a)), (0.0, -1.0, 0.0), "Brass", 0.005, 0.0035,
                             6)))
    return objs, [socket(rot_z=180.0), shape_cyl("Bumper", (0.0, 0.135, z), 0.045, 0.17)]


def build_Mod_Damper(base="PaintYellow"):
    """Амортизатор сустава: телескопическая стойка вдоль конечности у самого сустава — железный цилиндр, стальной шток, крашеная
    пружина поверх (Base_), латунные тарелки; два латунных ушка на болтах — у хомута сустава и у второго хомута ниже."""
    z = 0.092
    objs = _strap("MDA", 0.02)
    objs += _saddle("MDA", 0.035, 0.175, ang=45.0)
    for y in (0.012, 0.19):   # ушки на кронштейнах
        objs.append(fin(rbox("MDA_Bracket", (0.026, 0.026, 0.03), "Iron", (0.0, y, 0.077), 0.004, 1), angle=40))
        objs.append(fin(torus("MDA_Eye", (0.0, y, z), 0.0115, 0.0048, "Brass", 'XY', 14, 6), angle=60))
        objs.append(fin(stud("MDA_EyeBolt", (0.0, y, z + 0.002), (0.0, 0.0, 1.0), "Steel", 0.0065, 0.004, 6)))
    objs.append(band("MDA_Clamp", 0.19, 0.062, 0.018, "Iron"))
    objs.append(fin(revolve("MDA_Body", [(0.0, 0.022), (0.009, 0.022), (0.017, 0.032), (0.017, 0.108), (0.012, 0.112), (0.0, 0.112)], "Iron",
                            16, T((0.0, 0.0, z))), 0.0, angle=40, uv="cyl"))
    objs.append(fin(revolve("MDA_Rod", [(0.0, 0.108), (0.0075, 0.108), (0.0075, 0.178), (0.0, 0.18)], "Steel", 10, T((0.0, 0.0, z))),
                    angle=50))
    objs.append(fin(revolve("MDA_RodEnd", [(0.0, 0.172), (0.009, 0.172), (0.009, 0.181), (0.0, 0.181)], "Brass", 10, T((0.0, 0.0, z))),
                    angle=50))
    for y, r in ((0.044, 0.031), (0.163, 0.028)):   # тарелки пружины
        objs.append(fin(revolve("MDA_Seat", [(0.0, y - 0.004), (r, y - 0.004), (r + 0.002, y), (r, y + 0.004), (0.0, y + 0.004)], "Brass",
                                18, T((0.0, 0.0, z))), 0.0, angle=40, uv="cyl"))
    objs.append(_coil("MDA_Coil", 0.048, 0.159, 0.025, 0.025, 6.0, 0.0045, "Base_" + base, z=z, per_turn=10, sides=5))
    objs.append(fin(stud("MDA_Fitting", (0.017, 0.07, z), (1.0, 0.0, 0.0), "Brass", 0.005, 0.006, 6)))
    return objs, [socket(rot_z=180.0), shape_cyl("Damper", (0.0, 0.1, z), 0.033, 0.2)]


def build_Mod_Grinder(base="Rust"):
    """Наждак: гнутая абразивная накладка (Base_) на ударной стороне конечности поверх железной подложки; на ней ряды стальных
    зубьев-рашпиля, латунные болты по углам и хомут с пряжкой поперёк середины."""
    objs = _strap("MGR", 0.02)
    # радиусы — с запасом на ногу: накладка видна и на бедре (r 0.074), на руке (0.058) лист чуть отстоит
    objs.append(fin(_shell("MGR_Back", 0.03, 0.215, 0.062, 0.069, math.radians(72.0), "Iron", 12), 0.0015, 1, angle=50))
    objs.append(fin(_shell("MGR_Pad", 0.038, 0.207, 0.068, 0.076, math.radians(64.0), "Base_" + base, 12), 0.0015, 1, angle=50))
    rows = [0.05, 0.064, 0.078, 0.092, 0.106, 0.142, 0.156, 0.17, 0.184, 0.196]
    for i, y in enumerate(rows):
        n = 6 if i % 2 == 0 else 5
        span = math.radians(54.0) if n == 6 else math.radians(43.0)
        for a in _lin(-span, span, n):
            d = Vector((math.sin(a), 0.55, math.cos(a))).normalized()   # зуб рашпиля наклонён к кисти
            objs.append(fin(spike("MGR_Tooth", Vector((0.0, y, 0.0)) + Vector((math.sin(a), 0.0, math.cos(a))) * 0.0755, tuple(d), 0.011,
                                  0.0058, "Steel", 4), angle=20))
    for y in (0.036, 0.209):
        for s in (-1, 1):
            a = s * math.radians(67.0)
            nrm = Vector((math.sin(a), 0.0, math.cos(a)))
            objs.append(fin(stud("MGR_Bolt", Vector((0.0, y, 0.0)) + nrm * 0.069, nrm, "Brass", 0.0062, 0.0042, 6)))
    objs += _strap("MGR_Mid", 0.124, 0.079)
    return objs, [socket(rot_z=180.0), shape_box("Grinder", (0.0, 0.12, 0.064), (0.15, 0.19, 0.048))]


# ---------------------------------------------------------------------------------------------------------------------------------
# спина (Anchor_Back, +Y — вверх, Z ≤ 0 — за спиной); обтекатель — и на макушку (Anchor_Top)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Mod_Battery(base="Iron"):
    """Батарея: широкий аккумулятор за спиной на железной раме (Base_ — корпус), чёрная эбонитовая крышка, клеммы сверху —
    красный «+» и железный «−», толстые кабели через плечи к плечевым суставам; светящиеся деления заряда на задней стенке,
    светлая полоса опасности."""
    zc, yc = -0.062, 0.04   # центр корпуса; верх (клеммы) над плечами — над ядром выступает от y ≈ 0.08
    objs = []
    for sx in (-1, 1):   # рама
        objs.append(fin(rbox("MBT_Frame", (0.03, 0.24, 0.018), "Iron", (sx * 0.095, yc + 0.01, -0.009), 0.005, 1), angle=40))
    objs.append(rbox("MBT_Case", (0.3, 0.2, 0.09), "Base_" + base, (0.0, yc, zc), 0.01, 2))
    objs.append(rbox("MBT_Lid", (0.306, 0.028, 0.096), "Rubber", (0.0, yc + 0.11, zc), 0.008, 2))
    objs.append(rbox("MBT_Stripe", (0.304, 0.032, 0.094), "Bone", (0.0, yc - 0.058, zc), 0.006, 1))
    for k in range(6):   # косые полосы опасности на задней стенке
        x = -0.125 + k * 0.05
        slash = [(x, yc - 0.073), (x + 0.018, yc - 0.073), (x + 0.03, yc - 0.043), (x + 0.012, yc - 0.043)]
        objs.append(fin(extrude2d("MBT_Hazard", slash, zc - 0.0485, zc - 0.0465, "Rubber"), 0.0, angle=30))
    for sx, cap, sign in ((1, "Gem", "+"), (-1, "Iron", "-")):   # клеммы: латунный столбик, колпачок, знак
        x = sx * 0.105
        objs.append(fin(revolve("MBT_Post", [(0.0, 0.12), (0.012, 0.12), (0.012, 0.136), (0.0, 0.136)], "Brass", 12, T((x, yc, zc))),
                        angle=50))
        objs.append(fin(revolve("MBT_Cap", [(0.0, 0.132), (0.02, 0.132), (0.022, 0.138), (0.018, 0.15), (0.0, 0.153)], cap, 16,
                                T((x, yc, zc))), 0.0, angle=50, uv="cyl"))
        objs.append(fin(box("MBT_Sign", (0.016, 0.004, 0.004), "Bone", (x, yc + 0.154, zc)), 0.0))
        if sign == "+":
            objs.append(fin(box("MBT_Sign", (0.004, 0.004, 0.016), "Bone", (x, yc + 0.154, zc)), 0.0))
        # кабель от клеммы через плечо вперёд, к плечевому суставу: спереди — чёрная петля над плечом сбоку от головы
        cable = [Vector((x + sx * 0.014, yc + 0.13, zc)), Vector((sx * 0.14, yc + 0.158, zc + 0.008)),
                 Vector((sx * 0.182, yc + 0.162, zc + 0.04)), Vector((sx * 0.206, yc + 0.128, zc + 0.085)),
                 Vector((sx * 0.205, yc + 0.08, zc + 0.13)), Vector((sx * 0.192, yc + 0.045, zc + 0.16))]
        objs.append(fin(sweep("MBT_Cable", cable, 0.0075, "Rubber", sides=6), angle=60))
        objs.append(fin(revolve("MBT_Lug", [(0.0, -0.004), (0.011, -0.004), (0.011, 0.012), (0.0, 0.014)], "Brass", 10,
                                align_y(cable[0] - cable[1], cable[0] + (cable[1] - cable[0]).normalized() * 0.008)), angle=50))
    # деления заряда на задней стенке: три горят, четвёртое тёмное
    objs.append(fin(rbox("MBT_Gauge", (0.16, 0.05, 0.008), "Iron", (0.0, yc + 0.035, zc - 0.047), 0.003, 1), angle=40))
    for k in range(4):
        objs.append(fin(box("MBT_Cell", (0.03, 0.032, 0.006), "CoreGlow" if k < 3 else "Screen",
                            (-0.054 + k * 0.036, yc + 0.035, zc - 0.05)), 0.0015, 1))
    objs.append(sphere("MBT_Led", 0.0075, (0.0, yc + 0.126, zc - 0.03), "CoreGlow", 10, 5))
    return objs, [socket(rot_z=180.0), shape_box("Battery", (0.0, yc + 0.02, zc), (0.31, 0.26, 0.1))]


def build_Mod_Flywheel(base="Iron"):
    """Маховик: тяжёлое спицевое колесо Ø 0.4 за спиной, плоскостью к камере (видно над плечами по бокам головы), Base_ — обод и спицы;
    латунная ступица с гайкой на оси, железная плита-кронштейн с бобышкой, светлые метки на ободе — видно вращение."""
    c = Vector((0.0, 0.15, 0.0))   # ось выше плеч: обод (r 0.2) выглядывает спереди дугами по бокам головы (голова ±0.18)
    objs = [fin(rbox("MFW_Mount", (0.11, 0.21, 0.02), "Iron", (0.0, 0.06, -0.01), 0.005, 1), angle=40)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(fin(stud("MFW_MountBolt", (sx * 0.04, 0.06 + sy * 0.085, -0.02), (0.0, 0.0, -1.0), "Brass", 0.0065, 0.0042, 6)))
    objs.append(fin(_disc_z("MFW_Boss", [(0.0, -0.016), (0.03, -0.016), (0.03, -0.04), (0.022, -0.05), (0.0, -0.05)], "Iron", c, 18),
                    0.0, angle=40, uv="cyl"))
    objs.append(fin(revolve("MFW_Rim", [(0.166, -0.089), (0.192, -0.089), (0.199, -0.082), (0.199, -0.058), (0.192, -0.051),
                                        (0.166, -0.051), (0.161, -0.07)], "Base_" + base, 40, T(c) @ Rx(90.0), closed=True),
                    0.0, angle=40, uv="cyl", axis='Z'))
    for k in range(6):   # спицы, чуть изогнутые (читаются как вращение)
        a = TAU * k / 6 + 0.2
        pts = [c + Vector((r * math.cos(a + da), r * math.sin(a + da), -0.07)) for r, da in ((0.03, 0.0), (0.1, 0.14), (0.168, 0.22))]
        objs.append(fin(sweep("MFW_Spoke", pts, [0.014, 0.011, 0.0105], "Base_" + base, sides=6), angle=50))
    objs.append(fin(_disc_z("MFW_Hub", [(0.0, -0.048), (0.033, -0.048), (0.038, -0.054), (0.038, -0.086), (0.033, -0.092),
                                        (0.0, -0.092)], "Brass", c, 20), 0.0, angle=40, uv="cyl"))
    objs.append(fin(_disc_z("MFW_Nut", [(0.0, -0.09), (0.017, -0.09), (0.017, -0.102), (0.012, -0.106), (0.0, -0.106)], "Iron", c, 6),
                    0.0, angle=30))
    objs.append(fin(_disc_z("MFW_Axle", [(0.0, -0.104), (0.007, -0.104), (0.007, -0.112), (0.0, -0.114)], "Steel", c, 10), angle=50))
    for a0 in (math.radians(25.0), math.radians(155.0), math.radians(270.0)):   # метки на ободе: к камере (z −0.051) и назад (−0.089)
        quad = [(c.x + r * math.cos(a0 + s * 0.06), c.y + r * math.sin(a0 + s * 0.06)) for r, s in ((0.17, -1), (0.194, -1), (0.194, 1),
                                                                                                   (0.17, 1))]
        objs.append(fin(extrude2d("MFW_Mark", quad, -0.0515, -0.0495, "Bone"), 0.0))
        objs.append(fin(extrude2d("MFW_Mark", quad, -0.0905, -0.0885, "Bone"), 0.0))
    for k in range(10):   # болты обода к камере
        a = TAU * k / 10 + 0.6
        objs.append(fin(stud("MFW_RimBolt", (c.x + 0.18 * math.cos(a), c.y + 0.18 * math.sin(a), -0.051), (0.0, 0.0, 1.0), "Brass", 0.006,
                             0.004, 6)))
    # столкновение — только ступица с кронштейном: колесо 0.4 м формой раздувало инерцию ядра вдвое, и раскрутка с маховиком
    # выходила медленнее, чем без него (part_mods_probe)
    return objs, [socket(rot_z=180.0), shape_box("Flywheel", (0.0, 0.12, -0.05), (0.16, 0.2, 0.06))]


# обтекатель: наружный профиль (r, y) от борта до острия; лист 4 мм; наклон острия назад
_FAIRING = [(0.072, 0.0), (0.079, 0.018), (0.08, 0.036), (0.077, 0.056), (0.07, 0.08), (0.059, 0.104), (0.045, 0.128), (0.03, 0.15),
            (0.016, 0.168), (0.006, 0.178), (0.0, 0.182)]
_FAIR_XF = T((0.0, 0.0, -0.04)) @ Rx(-12.0)


def _fair_r(y):
    for (r0, y0), (r1, y1) in zip(_FAIRING, _FAIRING[1:]):
        if y0 <= y <= y1:
            return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
    return 0.0


def build_Mod_Fairing(base="PaintWhite"):
    """Обтекатель: лёгкий клёпаный колпак-капля из тонкого листа на макушку (или за спину), острие отклонено назад; завальцованный
    железный борт, тонкая полоска цвета игрока поясом и вдоль лба, три железные лапки на болтах."""
    inner = [(max(r - 0.004, 0.0), y - (0.006 if r < 0.01 else 0.0)) for r, y in reversed(_FAIRING)]
    objs = [fin(revolve("MFR_Shell", _FAIRING + inner, "Base_" + base, 24, _FAIR_XF, closed=True), 0.0, angle=50, uv="cyl")]
    objs.append(fin(revolve("MFR_Bead", [(0.07, -0.004), (0.077, -0.001), (0.077, 0.006), (0.07, 0.009)], "Iron", 24, _FAIR_XF, closed=True),
                    angle=60))
    yb = 0.05
    rb = _fair_r(yb) + 0.0008
    objs.append(fin(revolve("MFR_Pin", [(rb, yb - 0.004), (rb + 0.0012, yb - 0.002), (rb + 0.0012, yb + 0.002), (rb, yb + 0.004)],
                            "Shirt_Kit", 24, _FAIR_XF, closed=True), angle=60))
    stripe = [_FAIR_XF @ Vector((0.0, y, _fair_r(y) + 0.0012)) for y in _lin(yb + 0.006, 0.168, 8)]
    objs.append(fin(sweep("MFR_Stripe", stripe, [0.0028] * 7 + [0.0016], "Shirt_Kit", sides=4), angle=60))
    for s in (-1, 1):   # клёпаные швы по бокам
        for y in _lin(0.02, 0.13, 5):
            r = _fair_r(y)
            n = _FAIR_XF.to_3x3() @ Vector((s, 0.0, 0.0))
            objs.append(fin(stud("MFR_Rivet", _FAIR_XF @ Vector((s * r, y, 0.0)), tuple(n), "Brass", 0.0045, 0.003, 6)))
    for k in range(3):   # лапки крепления у борта
        a = TAU * k / 3 + math.pi / 2
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        p = _FAIR_XF @ (d * 0.084 + Vector((0.0, 0.004, 0.0)))
        objs.append(fin(rbox("MFR_Tab", (0.022, 0.01, 0.022), "Iron", tuple(p), 0.003, 1), angle=40))
        objs.append(fin(stud("MFR_TabBolt", tuple(p + Vector((0.0, 0.005, 0.0))), (0.0, 1.0, 0.0), "Brass", 0.005, 0.0035, 6)))
    return objs, [socket(rot_z=180.0), shape_cyl("Fairing", (0.0, 0.088, -0.05), 0.08, 0.18)]


def build_Mod_Repair(base="PaintGreen"):
    """Скобы-ремкомплект: ящик из тёмного дерева за спиной (крышка — Base_), железные оковки и ручка, латунная защёлка; сбоку над
    плечом — сварочная горелка с латунной ручкой и резиновым шлангом, на сопле — искра; с другой стороны в зажиме торчат скобы."""
    zc = -0.061
    objs = [fin(rbox("MRP_Mount", (0.14, 0.04, 0.016), "Iron", (0.0, 0.0, -0.008), 0.004, 1), angle=40)]
    objs.append(rbox("MRP_Box", (0.22, 0.12, 0.09), "WoodDark", (0.0, 0.0, zc), 0.006, 1))
    for sx in (-1, 1):
        objs.append(fin(box("MRP_Band", (0.014, 0.124, 0.094), "Iron", (sx * 0.075, -0.001, zc)), 0.002, 1))
    objs.append(rbox("MRP_Lid", (0.228, 0.026, 0.096), "Base_" + base, (0.0, 0.072, zc), 0.006, 2))
    objs.append(fin(sweep("MRP_Handle", [Vector((0.05 * math.cos(math.pi * k / 6), 0.085 + 0.03 * math.sin(math.pi * k / 6), zc))
                                         for k in range(7)], 0.006, "Iron", sides=6), angle=60))
    objs.append(fin(rbox("MRP_Latch", (0.03, 0.03, 0.01), "Brass", (0.0, 0.052, zc - 0.048), 0.003, 1), angle=40))
    for w, h in ((0.05, 0.014), (0.014, 0.05)):   # знак «+» на задней стенке
        objs.append(fin(box("MRP_Cross", (w, h, 0.004), "Bone", (0.0, -0.01, zc - 0.046)), 0.001, 1))
    # горелка: ручка вдоль d, шея загибается наружу к f, сопло, искра
    d = Vector((0.15, 1.0, 0.0)).normalized()
    f = Vector((1.0, 0.35, 0.0)).normalized()
    p0 = Vector((0.125, -0.04, zc + 0.006))
    p1 = p0 + d * 0.11
    objs.append(fin(rbox("MRP_Clip", (0.02, 0.03, 0.04), "Iron", (0.116, 0.0, zc + 0.006), 0.003, 1), angle=40))
    objs.append(fin(revolve("MRP_Torch", [(0.0, 0.0), (0.011, 0.0), (0.013, 0.01), (0.013, 0.1), (0.01, 0.11), (0.0, 0.11)], "Brass", 12,
                            align_y(d, p0)), 0.0, angle=50, uv="cyl"))
    for t in (0.02, 0.034, 0.048):
        objs.append(fin(revolve("MRP_Grip", [(0.0128, t - 0.004), (0.0145, t - 0.002), (0.0145, t + 0.002), (0.0128, t + 0.004)], "Rubber",
                                12, align_y(d, p0), closed=True), angle=60))
    objs.append(fin(stud("MRP_Valve", tuple(p0 + d * 0.085 + Vector((0.0, 0.0, -0.012))), (0.0, 0.0, -1.0), "Iron", 0.007, 0.008, 6)))
    neck = [p1 - d * 0.005, p1 + d * 0.03, p1 + d * 0.05 + f * 0.012, p1 + d * 0.055 + f * 0.04]
    objs.append(fin(sweep("MRP_Neck", neck, 0.0055, "Iron", sides=6), angle=60))
    tip = neck[-1]
    objs.append(fin(revolve("MRP_Nozzle", [(0.0, -0.002), (0.0085, -0.002), (0.0075, 0.02), (0.0045, 0.026), (0.0, 0.026)], "Brass", 10,
                            align_y(f, tip)), 0.0, angle=50, uv="cyl"))
    spark = tip + f * 0.036
    objs.append(sphere("MRP_Spark", 0.008, tuple(spark), "CoreGlow", 10, 5))
    for k in range(5):
        a = TAU * k / 5 + 0.3
        ray = (f * 0.6 + Vector((0.0, math.cos(a), math.sin(a))) * 0.8).normalized()
        objs.append(spike("MRP_Ray", tuple(spark), tuple(ray), 0.02, 0.0028, "CoreGlow", 4))
    # шланг: петлёй из торца ручки в бок ящика (x = 0.11)
    hose = [p0 + Vector((0.0, 0.004, 0.0)), p0 + Vector((0.002, -0.02, 0.006)), p0 + Vector((-0.004, -0.034, 0.01)),
            p0 + Vector((-0.016, -0.03, 0.01)), Vector((0.104, -0.045, zc + 0.012))]
    objs.append(fin(sweep("MRP_Hose", hose, 0.0055, "Rubber", sides=6), angle=60))
    # скобы в зажиме на другой стороне
    objs.append(fin(rbox("MRP_StapleClip", (0.07, 0.04, 0.07), "Iron", (-0.14, 0.05, zc), 0.004, 1), angle=40))
    u = [(-0.016, -0.1), (-0.016, -0.004), (-0.012, 0.0), (0.012, 0.0), (0.016, -0.004), (0.016, -0.1)]
    for k in range(3):   # скобы веером: ноги сходятся в зажим, верх — над плечом снаружи головы (|x| ≈ 0.17–0.2)
        xf = T((-0.17 - 0.015 * k, 0.165 - 0.015 * k, zc + 0.022 - 0.022 * k)) @ Rz(12.0 + 12.0 * k)
        pts = [xf @ Vector((x, y, 0.0)) for x, y in u]
        objs.append(fin(sweep("MRP_Staple", pts, [0.0028, 0.0045, 0.0045, 0.0045, 0.0045, 0.0028], "Steel", sides=4), angle=30))
    return objs, [socket(rot_z=180.0), shape_box("Repair", (0.0, 0.03, zc), (0.3, 0.24, 0.1))]


META = {
    "Mod_Servo": {"kind": "deco", "title": "Сервопривод", "mass": 1.4, "energy": 6},
    "Mod_Battery": {"kind": "deco", "title": "Батарея", "mass": 1.2, "energy": 5},
    "Mod_Sail": {"kind": "deco", "title": "Парус-щит", "mass": 1.6, "energy": 5},
    "Mod_Flywheel": {"kind": "deco", "title": "Маховик", "mass": 2.0, "energy": 6},
    "Mod_Bumper": {"kind": "deco", "title": "Пружина-отбойник", "mass": 0.8, "energy": 3},
    "Mod_Fairing": {"kind": "deco", "title": "Обтекатель", "mass": 0.6, "energy": 4},
    "Mod_Damper": {"kind": "deco", "title": "Амортизатор сустава", "mass": 0.9, "energy": 4},
    "Mod_Repair": {"kind": "deco", "title": "Скобы-ремкомплект", "mass": 1.0, "energy": 6},
    "Mod_Grinder": {"kind": "deco", "title": "Наждак", "mass": 0.8, "energy": 4},
}
