"""Детали профессиональной лиги Земли (листы автора 04.10.2026 «Профессиональная лига Земли — модули для серьёзного спорта»;
описание — docs/plan-demo/AI_ASSET_BRIEF.md). Контракт — как у остального кита (docs/plan-demo/BODY_KIT.md).

Язык набора — спортивная техника, а не игрушка:
  • кремовые скорлупы брони поверх тёмной рамы: скорлупа — Base_<Mat> (ось материалов: перекраска в мастерской, физика по
    материалу), рама и крепёж — Iron / Steel / Rubber / Brass кита;
  • акцентные полосы (на листах красные и синие) — цвет игрока Shirt_Kit; у ядер — широкий пояс (BODY_KIT.md §1);
  • голубой свет — линзы, сопла, огни состояния, кромка клинка; оранжевый — порт реактора и кольцо молота;
  • круглые поды с линзой, латунные ободки, болты под ключ.
Роли Pro_* не перекрашиваются (.tres пишет Godot-builder по PRO_MATS):
    Pro_Glow    голубое свечение — линзы, сопла, огни состояния, кромка клинка
    Pro_Carbon  матовый карбон, почти чёрный — шар реактора, подкладка под скорлупами, лицевые панели, клинок, лопасти
    Pro_Heat    оранжевое свечение — кольцо порта реактора, кольцо бойка молота
Удар формой (META hit_mult): клешня ×1.15, дробилка и стопа-копьё ×1.2."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
import common as C  # noqa: F401
import craft_parts as K  # noqa: F401
from kit_cores import _boss, _player_band, _prof_r, _ribbon, _rot
from kit_ends import _zrev
from kit_weapons import _collar

# роль → (база RGBA, шероховатость, металличность, эмиссия RGB | None, сила эмиссии в кадре Blender, альфа)
PRO_MATS = {
    "Pro_Glow": ((0.03, 0.2, 0.7, 1.0), 0.3, 0.0, (0.02, 0.3, 1.0), 1.0, 1.0),
    "Pro_Carbon": ((0.018, 0.019, 0.022, 1.0), 0.6, 0.2, None, 0.0, 1.0),
    "Pro_Heat": ((0.45, 0.15, 0.03, 1.0), 0.3, 0.0, (1.0, 0.4, 0.05), 1.5, 1.0),
}


def _mats():
    """Материалы ролей Pro_* для этого запуска Blender: в экспорте — плоские (имя = роль, настоящие ставит Godot),
    в кадре — с эмиссией. Кэш craft_parts (K._MATS) чистится на каждую деталь — вызывать в builder-е."""
    for role, (base, rough, metal, em, es, alpha) in PRO_MATS.items():
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


# ---------------------------------------------------------------------------------------------------------------------------------
# общие узлы языка про-лиги
# ---------------------------------------------------------------------------------------------------------------------------------
def _arc(name, prof, a0, a1, mat, n=8, axis='Y'):
    """Сегмент тела вращения — скорлупа брони, полоса на кольце: замкнутый профиль [(r, h), …] протянут по дуге a0 → a1 (градусы),
    торцы закрыты. axis='Y' — вокруг оси детали, угол от +Z (к камере) к +X; axis='Z' — вокруг оси к камере, угол от +X к +Y
    (кольцо в плоскости кадра), h — вдоль Z."""
    rings = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        if axis == 'Y':
            rings.append([(rr * math.sin(a), h, rr * math.cos(a)) for rr, h in prof])
        else:
            rings.append([(rr * math.cos(a), rr * math.sin(a), h) for rr, h in prof])
    return loft(name, rings, mat)


def _lens(prefix, pos, d, r, rim="Iron", segs=14):
    """Линза про-лиги: обод с фаской (тёмный или латунный) и голубой светящийся купол; pos — центр на поверхности, d — куда смотрит."""
    xf = align_y(d, pos)
    ring = revolve(prefix + "_LensRim", [(r * 0.9, -0.004), (r * 1.34, -0.004), (r * 1.34, r * 0.24), (r * 1.14, r * 0.44),
                                         (r * 0.9, r * 0.3)], rim, segs, xf, closed=True)
    dome = revolve(prefix + "_Lens", [(r, 0.0), (r * 0.86, r * 0.32), (r * 0.5, r * 0.54), (0.0, r * 0.62)], "Pro_Glow", segs, xf)
    return [fin(ring, angle=50.0), fin(dome, angle=80.0)]


def _bez3(a, b, c, d, n):
    """n + 1 точек кубической кривой Безье a → d."""
    a, b, c, d = Vector(a), Vector(b), Vector(c), Vector(d)
    return [a * (1 - t) ** 3 + b * 3 * (1 - t) ** 2 * t + c * 3 * (1 - t) * t * t + d * t ** 3 for t in (i / n for i in range(n + 1))]


def _hub_anchors(dn, ds):
    """Раскладка якорей шара-ядра, как у Core_Ball: (имя, угол в плоскости XY, расстояние от центра); плечи на 46° — в коридоре
    контракта (x 0.19+, y 0.20+), dn — шея / бока / бёдра, ds — плечи."""
    return [("Neck", 90.0, dn), ("Shoulder_L", 46.4, ds), ("Shoulder_R", 133.6, ds), ("Side_L", -5.0, dn), ("Side_R", 185.0, dn),
            ("Hip_L", -62.0, dn), ("Hip_R", -118.0, dn)]


def _dir(deg):
    return Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))


# ---------------------------------------------------------------------------------------------------------------------------------
# ядра (origin = центр; кадры якорей — HUMAN_ANCHORS, позиции — раскладка шара-ядра)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Core_ProGyro(base="PaintWhite"):
    """Ядро-гиростаб (лист 1, № 01): кремовый шар с большой голубой линзой в тёмной лицевой шайбе, вокруг в плоскости кадра —
    толстое кольцо-стабилизатор на четырёх тёмных спицах (крест); на кольце пять широких вставок цвета игрока, между шаром и
    кольцом — латунное кольцо подвеса с четырьмя круглыми подами-грузами (голубой огонёк в каждом). Суставы сидят на бобышках
    кольца, на спине — блок привода под якорь декора."""
    _mats()
    b = "Base_" + base
    R, Rr, hw, hd, ch = 0.125, 0.222, 0.026, 0.03, 0.01
    objs = [fin(sphere("CPG_Ball", R, (0, 0, 0), b, 24, 12), angle=60.0, uv="cyl")]
    objs.append(fin(_zrev("CPG_Face", [(0.0, 0.09), (0.086, 0.09), (0.086, 0.118), (0.076, 0.128), (0.0, 0.128)], "Pro_Carbon",
                          (0, 0, 0), 24), angle=50.0, uv="cyl", axis='Z'))
    objs += _lens("CPG_Eye", (0.0, 0.0, 0.128), (0, 0, 1), 0.05, rim="Brass", segs=24)
    # кольцо-стабилизатор: восьмигранное сечение 52 × 60 мм
    sec = [(-hw, -hd + ch), (-hw + ch, -hd), (hw - ch, -hd), (hw, -hd + ch), (hw, hd - ch), (hw - ch, hd), (-hw + ch, hd), (-hw, hd - ch)]
    objs.append(fin(_zrev("CPG_Ring", [(Rr + x, z) for x, z in sec], b, (0, 0, 0), 48, closed=True), angle=40.0, uv="cyl", axis='Z'))
    # вставки цвета игрока (BODY_KIT.md §1, «Цвет игрока на ядре»): то же сечение на 3 мм шире кольца, между бобышками суставов
    for a0, a1 in ((8.0, 36.0), (144.0, 172.0), (-52.0, -15.0), (-165.0, -128.0), (-106.0, -74.0)):
        objs.append(fin(_arc("CPG_PlayerBand", [(Rr + x * 1.12, z * 1.1) for x, z in sec], a0, a1, "Shirt_Kit",
                             max(3, int(round((a1 - a0) / 7.0))), axis='Z'), angle=40.0))
    for k in range(4):
        a = 45.0 + 90.0 * k
        objs.append(fin(box("CPG_Spoke", (0.1, 0.046, 0.034), "Iron", (0.152, 0.0, 0.0), Rz(a)), 0.008, 2, angle=60.0, bevel_angle=30.0))
        objs.append(fin(stud("CPG_SpokeBolt", tuple(_dir(a) * Rr + Vector((0.0, 0.0, hd))), (0, 0, 1), "Steel", 0.009, 0.006, 6)))
    # кольцо подвеса с подами-грузами
    Rg = 0.16
    objs.append(fin(torus("CPG_Gimbal", (0, 0, 0), Rg, 0.008, "Brass", 'XY', 40, 6), angle=80))
    for k in range(4):
        p = _dir(90.0 * k) * Rg
        objs.append(fin(sphere("CPG_Pod", 0.03, tuple(p), b, 12, 6), angle=70))
        objs += _lens("CPG_PodEye", tuple(p + Vector((0.0, 0.0, 0.026))), (0, 0, 1), 0.012, segs=10)
    empties = []
    for nm, deg, dist in _hub_anchors(0.275, 0.295):
        d = _dir(deg)
        h = dist - 0.236 - 0.022
        objs.append(fin(revolve("CPG_Boss", [(0.0, 0.0), (0.04, 0.0), (0.04, h - 0.006), (0.034, h), (0.0, h)], "Iron", 14,
                                align_y(d, d * 0.236)), angle=50.0, uv="cyl"))
        empties.append(anchor(nm, tuple(d * dist), _rot(nm)))
    objs.append(rbox("CPG_Pack", (0.1, 0.11, 0.07), "Iron", (0.0, 0.095, -0.108), 0.014, 2))
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), 0.235))
    return objs, empties


def build_Core_ProReactor(base="PaintWhite"):
    """Ядро-реактор (лист 1, № 02; лист 2, № 02): тяжёлый карбоновый шар, на верхней половине четыре кремовые скорлупы с зазорами,
    в груди — порт реактора (тёмный обод на латунных болтах, оранжевое кольцо, светящееся окно Ядра), под ним широкий пояс
    цвета игрока; кремовые круглые поды плеч с огоньком и поды бёдер, сверху — латунный вентиль с маховиком (на нём шея)."""
    _mats()
    b = "Base_" + base
    R = 0.19

    def rad(y):
        return math.sqrt(max(R * R - y * y, 0.0))

    objs = [fin(sphere("CPR_Ball", R, (0, 0, 0), "Pro_Carbon", 28, 14), angle=60.0, uv="cyl")]
    # скорлупы: сферический пояс от 23° до 62° широты, поднят над шаром на 12 мм, зазоры по 12° спереди, сзади и с боков
    lats = [math.radians(23.0 + 39.0 * i / 5) for i in range(6)]
    prof = [((R + 0.012) * math.cos(f), (R + 0.012) * math.sin(f)) for f in lats]
    prof += [((R - 0.004) * math.cos(f), (R - 0.004) * math.sin(f)) for f in reversed(lats)]
    for k in range(4):
        objs.append(fin(_arc("CPR_Shell", prof, 6.0 + 90.0 * k, 84.0 + 90.0 * k, b, 6), 0.003, 1, angle=40.0))
    f = math.radians(40.0)
    for a in (-65.0, -20.0, 20.0, 65.0):
        n = Vector((math.cos(f) * math.sin(math.radians(a)), math.sin(f), math.cos(f) * math.cos(math.radians(a))))
        objs.append(fin(stud("CPR_ShellBolt", tuple(n * (R + 0.012)), tuple(n), "Steel", 0.008, 0.005, 6)))
    objs.append(_player_band("CPR_PlayerBand", -0.06, -0.16, rad, lift=0.009, segs=28, steps=4))
    # порт реактора: обод вдоль Z, внутри — окно Ядра (CoreGlow) и оранжевое кольцо по кромке
    r_out, r_in, z0, z1 = 0.098, 0.07, 0.14, 0.206
    objs.append(fin(_zrev("CPR_Port", [(r_out, z0), (r_out, z1 - 0.012), (r_out - 0.01, z1), (r_in + 0.008, z1), (r_in, z1 - 0.008),
                                       (r_in, z0)], "Iron", (0, 0, 0), 28, closed=True), angle=40.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("CPR_PortGlow", [(r_in, z1 - 0.034), (r_in * 0.82, z1 - 0.02), (r_in * 0.45, z1 - 0.011), (0.0, z1 - 0.008)],
                          "CoreGlow", (0, 0, 0), 24), angle=80.0))
    objs.append(torus("CPR_PortHeat", (0.0, 0.0, z1 - 0.014), r_in - 0.004, 0.006, "Pro_Heat", 'XY', 28, 5))
    for k in range(8):
        a = TAU * k / 8 + math.pi / 8
        objs.append(fin(stud("CPR_PortBolt", (math.cos(a) * 0.086, math.sin(a) * 0.086, z1 - 0.003), (0, 0, 1), "Brass", 0.007,
                             0.005, 6)))
    # вентиль: фланец на макушке закрывает стык скорлуп, латунный корпус, стальной маховик; шар шеи садится на корпус
    objs.append(fin(revolve("CPR_Flange", [(0.0, 0.165), (0.09, 0.165), (0.092, 0.176), (0.078, 0.186), (0.0, 0.186)], "Iron", 24),
                    angle=50.0, uv="cyl"))
    objs.append(fin(revolve("CPR_Valve", [(0.0, 0.18), (0.058, 0.18), (0.058, 0.206), (0.05, 0.216), (0.04, 0.228), (0.0, 0.232)],
                            "Brass", 18), angle=50.0, uv="cyl"))
    objs.append(fin(torus("CPR_Wheel", (0.0, 0.2, 0.0), 0.08, 0.007, "Steel", 'XZ', 24, 5), angle=80))
    for pts in ([(-0.08, 0.2, 0.0), (0.08, 0.2, 0.0)], [(0.0, 0.2, -0.08), (0.0, 0.2, 0.08)]):
        objs.append(fin(sweep("CPR_WheelSpoke", pts, 0.005, "Steel", sides=5), angle=60))
    empties = []
    for nm, deg, dist in _hub_anchors(0.262, 0.283):
        d = _dir(deg)
        if nm.startswith("Shoulder"):
            c = d * 0.212
            objs.append(fin(sphere("CPR_Pod", 0.066, tuple(c), b, 16, 8), angle=70))
            objs.append(fin(revolve("CPR_PodSeat", [(0.05, -0.008), (0.07, -0.008), (0.072, 0.004), (0.064, 0.012), (0.05, 0.012)],
                                    "Iron", 18, align_y(d, d * 0.234), closed=True), angle=50.0))
            objs += _lens("CPR_PodEye", tuple(c + Vector((0.0, 0.0, 0.062))), (0, 0, 1), 0.013, segs=10)
        elif nm.startswith("Hip"):
            objs.append(fin(sphere("CPR_HipPod", 0.054, tuple(d * 0.203), b, 14, 7), angle=70))
        elif nm.startswith("Side"):
            objs += _boss("CPR_Side", tuple(d * (R - 0.004)), tuple(d), 0.044, 0.036, segs=14)
        empties.append(anchor(nm, tuple(d * dist), _rot(nm)))
    objs += _boss("CPR_BackPad", (0.0, 0.14, -0.126), (0, 0, -1), 0.03, 0.016, segs=12)
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), 0.2))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# головы (origin = шея, растут вверх; FacePlate — экран / визор с фото пилота)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Head_ProVisor(base="PaintWhite"):
    """Голова-визор (лист 1, № 03): кремовый короб со скруглением, во весь лоб — широкий экран в карбоновой рамке (FacePlate —
    сам экран), под ним голубой огонёк состояния; по бокам круглые поды-линзы (смотрят вперёд и наружу, воротник цвета игрока),
    на макушке полоса цвета игрока, болты по углам лица."""
    _mats()
    b = "Base_" + base
    c = (0.0, 0.2, 0.0)
    shell = box("HPV_Shell", (0.31, 0.27, 0.26), b, c)
    K.bevel_apply(shell, 0.045, 3, 30.0)          # фаска ДО выреза: иначе кромки выреза зажимают её (clamp overlap)
    cut_box(shell, (0.0, 0.21, 0.14), (0.225, 0.185, 0.06))
    objs = [fin(shell, 0.0, angle=50.0)]
    objs.append(rounded_frame("HPV_Bezel", (0.0, 0.21), 0.112, 0.092, 0.013, "Pro_Carbon", 0.128))
    objs.append(fin(box("HPV_Status", (0.044, 0.01, 0.012), "Pro_Glow", (0.0, 0.086, 0.119)), 0.002, 1))
    for sx in (-1, 1):
        pc = Vector((sx * 0.158, 0.2, 0.012))
        d = Vector((sx * 0.6, 0.0, 0.8))
        objs.append(fin(sphere("HPV_Pod", 0.05, tuple(pc), b, 16, 8), angle=70))
        objs.append(fin(revolve("HPV_PodCollar", [(0.024, -0.004), (0.036, -0.004), (0.036, 0.004), (0.024, 0.006)], "Shirt_Kit", 16,
                                align_y(d, pc + d * 0.036), closed=True), angle=50.0))
        objs += _lens("HPV_PodEye", tuple(pc + d * 0.042), tuple(d), 0.021, segs=14)
        for y in (0.092, 0.31):
            objs.append(fin(stud("HPV_Bolt", (sx * 0.132, y, 0.123), (sx * 0.25, 0.25 if y > 0.2 else -0.25, 1.0), "Steel", 0.007,
                                 0.0045, 6)))
    objs.append(rbox("HPV_Stripe", (0.07, 0.012, 0.19), "Shirt_Kit", (0.0, 0.334, 0.0), 0.004, 1))
    objs += neck_stub("HPV")
    face = face_plate("FacePlate", (0.0, 0.21, 0.117), 0.212, 0.172, cols=10, rows=8, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.342, 0.0), 180.0), shape_box("Head", c, (0.31, 0.27, 0.26))]
    return objs, empties, [face]


def build_Head_ProPilot(base="PaintWhite"):
    """Шлем пилота (лист 2, № 03): округлый гоночный шлем — кремовая скорлупа, спереди выступает литой короб визора (FacePlate —
    стекло визора в карбоновой рамке), под ним карбоновая дуга-подбородник с огоньком, полоса цвета игрока от визора через макушку
    к затылку, по бокам камеры на латунных ободах с голубой линзой (смотрят вперёд), на макушке крышка вентиляции."""
    _mats()
    b = "Base_" + base
    prof = [(0.0, 0.368), (0.05, 0.362), (0.095, 0.34), (0.128, 0.3), (0.148, 0.25), (0.155, 0.2), (0.152, 0.14), (0.14, 0.09),
            (0.12, 0.06), (0.09, 0.045), (0.0, 0.045)]
    shell = revolve("HPP_Shell", prof, b, 28)
    cut_box(shell, (0.0, 0.205, 0.16), (0.19, 0.126, 0.12))   # скорлупа не выпирает в окно визора: за стеклом — дно короба
    objs = [fin(shell, 0.0, angle=50.0, uv="cyl")]
    hood = box("HPP_Visor", (0.22, 0.155, 0.072), b, (0.0, 0.205, 0.122))
    K.bevel_apply(hood, 0.022, 3, 30.0)
    cut_box(hood, (0.0, 0.205, 0.16), (0.186, 0.122, 0.05))
    objs.append(fin(hood, 0.0, angle=50.0))
    objs.append(rounded_frame("HPP_Bezel", (0.0, 0.205), 0.09, 0.058, 0.008, "Pro_Carbon", 0.152))
    objs.append(fin(_arc("HPP_Chin", [(0.118, 0.05), (0.15, 0.06), (0.167, 0.088), (0.167, 0.116), (0.152, 0.124), (0.13, 0.1)],
                         -64.0, 64.0, "Pro_Carbon", 10), 0.003, 1, angle=40.0))
    objs.append(fin(box("HPP_Status", (0.034, 0.012, 0.01), "Pro_Glow", (0.0, 0.1, 0.168)), 0.002, 1))
    for sx in (-1, 1):
        objs.append(fin(stud("HPP_ChinBolt", (sx * 0.167 * math.sin(math.radians(50.0)), 0.1, 0.167 * math.cos(math.radians(50.0))),
                             (sx * 0.77, 0.0, 0.64), "Steel", 0.008, 0.005, 6)))
        objs.append(fin(revolve("HPP_Cam", [(0.0, 0.0), (0.04, 0.0), (0.046, 0.008), (0.046, 0.076), (0.04, 0.086), (0.0, 0.086)],
                                "Iron", 18, align_y((0, 0, 1), (sx * 0.166, 0.215, -0.03))), angle=50.0))
        objs += _lens("HPP_CamEye", (sx * 0.166, 0.215, 0.056), (0, 0, 1), 0.025, rim="Brass", segs=16)
    # полоса цвета игрока по меридиану: от верхней кромки визора через макушку к затылку
    hc = Vector((0.0, 0.2, 0.0))
    pts = [Vector((0.0, y, _prof_r(prof, y))) for y in (0.275, 0.3, 0.325, 0.345, 0.36)] + [Vector((0.0, 0.368, 0.0))]
    pts += [Vector((0.0, y, -_prof_r(prof, y))) for y in (0.36, 0.34, 0.3, 0.25, 0.2, 0.14)]
    objs.append(_ribbon("HPP_Stripe", pts, [p - hc for p in pts], 0.052, "Shirt_Kit", lift=0.004))
    objs.append(fin(revolve("HPP_Vent", [(0.0, 0.362), (0.04, 0.362), (0.043, 0.37), (0.034, 0.38), (0.0, 0.382)], "Iron", 16),
                    angle=50.0, uv="cyl"))
    objs += neck_stub("HPP")
    face = face_plate("FacePlate", (0.0, 0.205, 0.139), 0.182, 0.118)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.382, 0.0), 180.0), shape_sphere("Head", (0.0, 0.205, 0.0), 0.16)]
    return objs, empties, [face]


# ---------------------------------------------------------------------------------------------------------------------------------
# конечность (L, r, ja, jb — как у kit_limbs; размеры S / L даёт body_kit.sized)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Limb_ProPanel(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintWhite"):
    """Панельная — штатный сегмент про-лиги: тёмная труба-рама с обоймами на концах, на верхних 70 % — две длинные кремовые
    скорлупы (левая и правая, сужаются книзу) на карбоновой подкладке: в шве спереди голубой огонёк состояния, поверх — ремень
    цвета игрока, болты; под скорлупами резиновый отбойник, ниже рама открыта (стальной сальник) до нижней обоймы."""
    _mats()
    b = "Base_" + base
    ya, yb = ja * 0.6, L - jb * 0.6
    objs = [fin(revolve("LPP_Frame", [(0.0, -ya), (r * 0.6, -ya), (r * 0.56, -yb), (0.0, -yb)], "Iron", 14), uv="cyl")]
    objs += ferrule("LPP_TopCap", -ya + 0.012, -ya - 0.022, r * 0.96, rivets=0)
    objs += ferrule("LPP_BotCap", -yb + 0.03, -yb - 0.01, r * 0.88, rivets=0)
    top, bot = -ya - 0.022, -yb + 0.03
    t1, b1 = top - 0.004, top - (top - bot) * 0.7
    h = t1 - b1
    objs.append(fin(revolve("LPP_Liner", [(r * 0.86, t1 - 0.004), (r * 0.86, b1 + 0.004)], "Pro_Carbon", 16), uv="cyl"))
    prof = [(r * 1.0, t1), (r * 1.16, t1 - 0.012), (r * 1.2, t1 - h * 0.3), (r * 1.1, b1 + 0.016), (r * 0.98, b1), (r * 0.84, b1),
            (r * 0.84, t1)]
    ys = t1 - h * 0.3   # ремень цвета игрока — на самом широком месте скорлуп, на той же сетке углов (шов открыт)
    strap = [(r * 1.2 - 0.004, ys + 0.012), (r * 1.2 + 0.0035, ys + 0.009), (r * 1.2 + 0.0035, ys - 0.009), (r * 1.2 - 0.004, ys - 0.012)]
    for a0 in (10.0, 190.0):
        objs.append(fin(_arc("LPP_Shell", prof, a0, a0 + 160.0, b, 10), 0.003, 1, angle=40.0))
        objs.append(fin(_arc("LPP_Stripe", strap, a0 + 1.5, a0 + 158.5, "Shirt_Kit", 10), angle=40.0))
    objs.append(fin(box("LPP_Status", (0.012, h * 0.26, 0.012), "Pro_Glow", (0.0, t1 - h * 0.64, r * 1.08)), 0.002, 1))
    yr = b1 - 0.01
    objs.append(fin(revolve("LPP_Bumper", [(r * 0.7, yr + 0.009), (r * 1.1, yr + 0.009), (r * 1.18, yr + 0.003), (r * 1.18, yr - 0.003),
                                           (r * 1.1, yr - 0.009), (r * 0.7, yr - 0.009)], "Rubber", 22, closed=True), uv="cyl"))
    objs.append(band("LPP_Gland", (yr - 0.009 + bot) / 2, r * 0.66, 0.012, "Steel"))
    for sx in (-1, 1):
        for y, rr in ((t1 - h * 0.12, r * 1.165), (b1 + 0.024, r * 1.105)):
            n = Vector((sx * math.sin(math.radians(40.0)), 0.0, math.cos(math.radians(40.0))))
            objs.append(fin(stud("LPP_Bolt", Vector((0.0, y, 0.0)) + n * rr, n, "Steel", 0.0065, 0.0045, 6)))
    return objs, limb_empties(L, r * 1.05)


# ---------------------------------------------------------------------------------------------------------------------------------
# кисти и стопы (Socket в 0, кисть растёт в −Y; стопа: низ на y = −0.09, как у kit_ends)
# ---------------------------------------------------------------------------------------------------------------------------------
def _claw(prefix, ctrl, w0, half, mat, xf=None, split=0.64, n=14):
    """Коготь-пластина: осевая линия — кривая Безье ctrl в плоскости XY (xf переносит в другую плоскость), полуширина сходит
    от w0 у корня к острию, толщина 2·half; до доли split — тело (mat), дальше — наконечник цвета игрока."""
    pts = _bez3(*[(x, y, 0.0) for x, y in ctrl], n)
    left, right = [], []
    for i, p in enumerate(pts):
        tg = (pts[min(i + 1, n)] - pts[max(i - 1, 0)]).normalized()
        w = w0 * (1.0 - i / n) ** 0.8 + 0.003
        left.append((p.x - tg.y * w, p.y + tg.x * w))
        right.append((p.x + tg.y * w, p.y - tg.x * w))
    k = int(round(split * n))
    body = left[:k + 1] + list(reversed(right[:k + 1]))
    tip = left[k:] + list(reversed(right[k:]))
    return [fin(extrude2d(prefix, body, -half, half, mat, xf=xf), 0.004, 1, angle=40.0),
            fin(extrude2d(prefix + "Tip", tip, -half * 0.86, half * 0.86, "Shirt_Kit", xf=xf), 0.003, 1, angle=40.0)]


def build_Hand_ProClaw(base="PaintWhite"):
    """Клешня про (лист 2, № 04): манжет, карбоновая ладонь с огоньком, три изогнутых кремовых когтя-пластины с наконечниками
    цвета игрока — два в плоскости кадра (сходятся внутрь), третий к камере; латунные шайбы-оси у корней."""
    _mats()
    b = "Base_" + base
    objs = ferrule("HPC_Cuff", -0.012, -0.05, 0.046)
    objs.append(rbox("HPC_Palm", (0.096, 0.056, 0.072), "Pro_Carbon", (0.0, -0.076, 0.0), 0.016, 2))
    objs += _lens("HPC_Status", (0.0, -0.066, 0.036), (0, 0, 1), 0.009, segs=10)
    for sx in (-1, 1):
        ctrl = [(sx * 0.03, -0.086), (sx * 0.092, -0.112), (sx * 0.086, -0.19), (sx * 0.024, -0.236)]
        objs += _claw("HPC_Claw", ctrl, 0.027, 0.019, b)
        objs.append(fin(_zrev("HPC_Pivot", [(0.0, -0.023), (0.016, -0.023), (0.02, -0.019), (0.02, 0.019), (0.016, 0.023), (0.0, 0.023)],
                              "Brass", (sx * 0.036, -0.094, 0.0), 14), angle=50.0, uv="cyl", axis='Z'))
    # средний коготь — в плоскости YZ (к камере): тот же контур, повёрнутый вокруг Y
    ctrl = [(0.026, -0.092), (0.074, -0.118), (0.08, -0.17), (0.05, -0.212)]
    objs += _claw("HPC_ClawMid", ctrl, 0.021, 0.016, b, xf=Matrix.Rotation(math.radians(-90.0), 4, 'Y'), n=12)
    objs.append(fin(sphere("HPC_Knuckle", 0.017, (0.0, -0.098, 0.03), "Brass", 12, 6), angle=80))
    return objs, [socket(), shape_box("Hand", (0.0, -0.14, 0.0), (0.16, 0.19, 0.07))]


def build_Hand_ProCrusher(base="PaintWhite"):
    """Дробилка (лист 1, № 05): тяжёлый кулак-барабан вдоль руки — кремовый барабан на тёмной шейке, воротник цвета игрока,
    резиновый бандаж и железный на болтах, голубой огонёк; ударный торец — стальная плита с семью гранёными шипами."""
    _mats()
    b = "Base_" + base
    objs = ferrule("HCR_Cuff", -0.012, -0.05, 0.048)
    objs.append(fin(revolve("HCR_Neck", [(0.0, -0.044), (0.034, -0.044), (0.034, -0.068), (0.0, -0.068)], "Iron", 14), uv="cyl"))
    objs.append(fin(revolve("HCR_Drum", [(0.0, -0.06), (0.062, -0.06), (0.082, -0.072), (0.088, -0.088), (0.088, -0.18),
                                         (0.08, -0.192), (0.0, -0.192)], b, 22), angle=40.0, uv="cyl"))   # 22 — сетка band()
    objs.append(band("HCR_Stripe", -0.095, 0.09, 0.022, "Shirt_Kit"))
    objs.append(band("HCR_Band", -0.128, 0.0905, 0.014, "Rubber"))
    objs.append(band("HCR_BandLow", -0.168, 0.092, 0.024, "Iron"))
    objs += ring_rivets("HCR_Bolt", -0.168, 0.093, 8, "Steel", 0.008, phase=math.pi / 8)
    objs.append(fin(box("HCR_Status", (0.034, 0.011, 0.01), "Pro_Glow", (0.0, -0.147, 0.088)), 0.002, 1))
    objs.append(fin(revolve("HCR_Face", [(0.0, -0.188), (0.077, -0.188), (0.077, -0.2), (0.069, -0.205), (0.0, -0.205)], "Iron", 24),
                    angle=40.0, uv="cyl"))
    for k in range(7):
        a = TAU * k / 6
        p = (0.0, -0.204, 0.0) if k == 6 else (math.cos(a) * 0.048, -0.204, math.sin(a) * 0.048)
        objs.append(fin(spike("HCR_Stud", p, (0, -1, 0), 0.022, 0.015, "Steel", 4), angle=30.0))
    return objs, [socket(), shape_cyl("Hand", (0.0, -0.132, 0.0), 0.088, 0.15)]


def build_Foot_ProWheel(base="PaintWhite"):
    """Большое колесо (лист 2, № 08): колесо ⌀0.22 перед лодыжкой на оси вдоль Z — резиновая шина, кремовый диск-тарелка,
    кольцо цвета игрока, латунная ступица с голубым огнём, болты; низ шины на −0.09, центр — у оси сустава (колесо катится
    вокруг лодыжки). Форма — шар: круг в плоскости боя, катится."""
    _mats()
    b = "Base_" + base
    c = Vector((0.0, 0.02, 0.106))
    objs = ferrule("FPW_Cuff", -0.004, -0.036, 0.048, rivets=0)
    objs.append(rbox("FPW_Bracket", (0.034, 0.05, 0.05), "Iron", (0.0, -0.012, 0.05), 0.008, 1))
    objs.append(fin(_zrev("FPW_Axle", [(0.0, -0.076), (0.02, -0.076), (0.02, -0.02), (0.0, -0.02)], "Iron", c, 12), uv="cyl", axis='Z'))
    tyre = [(0.084, -0.026), (0.098, -0.03), (0.107, -0.026), (0.11, -0.014), (0.11, 0.014), (0.107, 0.026), (0.098, 0.03),
            (0.084, 0.026)]
    objs.append(fin(_zrev("FPW_Tyre", tyre, "Rubber", c, 36, closed=True), angle=60.0, uv="cyl", axis='Z'))
    disc = [(0.0, 0.022), (0.074, 0.022), (0.08, 0.028), (0.087, 0.028), (0.087, -0.027), (0.07, -0.022), (0.0, -0.022)]
    objs.append(fin(_zrev("FPW_Disc", disc, b, c, 32), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("FPW_Stripe", [(0.057, 0.02), (0.071, 0.02), (0.071, 0.0248), (0.057, 0.0248)], "Shirt_Kit", c, 32,
                          closed=True), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("FPW_Hub", [(0.022, 0.02), (0.036, 0.02), (0.036, 0.031), (0.03, 0.037), (0.022, 0.035)], "Brass", c, 20,
                          closed=True), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("FPW_HubLight", [(0.023, 0.028), (0.02, 0.039), (0.011, 0.045), (0.0, 0.047)], "Pro_Glow", c, 16), angle=80.0))
    for k in range(6):
        a = TAU * k / 6
        objs.append(fin(stud("FPW_Bolt", (c.x + math.cos(a) * 0.047, c.y + math.sin(a) * 0.047, c.z + 0.022), (0, 0, 1), "Steel",
                             0.0065, 0.0045, 6)))
    return objs, [socket(), shape_sphere("Foot", (0.0, c.y, 0.0), 0.11)]


def build_Foot_ProSpike(base="PaintWhite"):
    """Стопа-копьё (лист 2, № 10): манжет, зажим цвета игрока на болтах с голубым огоньком, тёмный воротник, два коротких уса и
    длинное кремовое перо ромбического сечения со стальным остриём — стопа-ходуля, острие на −0.26 (нога длиннее ботинка на 0.17)."""
    _mats()
    b = "Base_" + base
    objs = ferrule("FPS_Cuff", -0.004, -0.036, 0.05, rivets=0)
    objs.append(rbox("FPS_Clamp", (0.092, 0.04, 0.076), "Shirt_Kit", (0.0, -0.056, 0.0), 0.01, 2))
    objs.append(rbox("FPS_Collar", (0.074, 0.016, 0.062), "Iron", (0.0, -0.082, 0.0), 0.005, 1))
    objs.append(fin(box("FPS_Status", (0.026, 0.01, 0.008), "Pro_Glow", (0.0, -0.056, 0.039)), 0.002, 1))
    for sx in (-1, 1):
        objs.append(fin(stud("FPS_Bolt", (sx * 0.046, -0.056, 0.0), (sx, 0, 0), "Steel", 0.011, 0.006, 6)))
        objs.append(fin(spike("FPS_Prong", (sx * 0.034, -0.086, 0.0), (sx * 0.4, -1.0, 0.0), 0.062, 0.012, b, 6), angle=40.0))

    def section(y, hw, t):
        rw, tf = 0.35 * hw, 0.5 * t
        return [(hw, y, 0.0), (rw, y, tf), (0.0, y, t), (-rw, y, tf), (-hw, y, 0.0), (-rw, y, -tf), (0.0, y, -t), (rw, y, -tf)]

    st = [(-0.072, 0.03, 0.022), (-0.094, 0.042, 0.027), (-0.13, 0.038, 0.024), (-0.19, 0.026, 0.017), (-0.225, 0.0165, 0.012)]
    objs.append(fin(loft("FPS_Blade", [section(*s) for s in st], b), angle=30.0))
    tip = [(-0.223, 0.0175, 0.013), (-0.243, 0.0095, 0.007)]
    objs.append(fin(loft("FPS_Tip", [section(*s) for s in tip], "Steel", pole1=(0.0, -0.262, 0.0)), angle=30.0))
    return objs, [socket(), shape_capsule("Foot", (0.0, -0.15, 0.0), 0.028, 0.22)]


def build_Foot_ProProp(base="PaintWhite"):
    """Стопа-пропеллер (лист 1, № 09): перед лодыжкой и под ней — кремовая гондола вентилятора в кольце (ось к камере, как носок
    ботинка): резиновая губа канала, пять карбоновых лопастей-клиньев на тёмной ступице с голубым огнём, за ними голубое свечение сопла;
    пояс цвета игрока по гондоле. Низ гондолы на −0.09; форма — шар."""
    _mats()
    b = "Base_" + base
    k = 1.18                                   # масштаб гондолы: радиус 0.066·k = 0.078
    c = Vector((0.0, -0.09 + 0.066 * k, 0.064 * k))

    def sc(prof):
        return [(rr * k, z * k) for rr, z in prof]

    objs = ferrule("FPP_Cuff", -0.004, -0.034, 0.046, rivets=0)
    body = [(0.0, -0.05), (0.034, -0.046), (0.054, -0.034), (0.066, -0.012), (0.066, 0.018), (0.062, 0.032), (0.056, 0.037),
            (0.05, 0.034), (0.05, 0.004), (0.0, 0.004)]
    objs.append(fin(_zrev("FPP_Pod", sc(body), b, c, 28), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("FPP_Lip", sc([(0.047, 0.028), (0.047, 0.04), (0.052, 0.045), (0.058, 0.042), (0.059, 0.034), (0.052, 0.028)]),
                          "Rubber", c, 28, closed=True), angle=50.0, uv="cyl", axis='Z'))
    objs.append(fin(_zrev("FPP_Stripe", sc([(0.0655, 0.012), (0.0685, 0.009), (0.0685, -0.005), (0.0655, -0.008)]), "Shirt_Kit", c, 28,
                          closed=True), angle=50.0, uv="cyl", axis='Z'))
    objs.append(_zrev("FPP_Glow", sc([(0.0, 0.005), (0.049, 0.005), (0.049, 0.009), (0.0, 0.009)]), "Pro_Glow", c, 20))
    objs.append(fin(_zrev("FPP_Hub", sc([(0.0, 0.004), (0.017, 0.004), (0.017, 0.028), (0.011, 0.038), (0.0, 0.04)]), "Iron", c, 12),
                    angle=50.0, uv="cyl", axis='Z'))
    objs.append(sphere("FPP_HubLight", 0.009 * k, (c.x, c.y, c.z + 0.04 * k), "Pro_Glow", 10, 5))
    # лопасти — клинья без шага (шире к ободу): веер зеркально симметричен, правая стопа — зеркало левой без «обратного винта»
    blade = [(0.014 * k, -0.005 * k), (0.05 * k, -0.0125 * k), (0.05 * k, 0.0125 * k), (0.014 * k, 0.005 * k)]
    for i in range(5):
        xf = T((c.x, c.y, c.z + 0.024 * k)) @ Rz(72.0 * i + 18.0)
        objs.append(fin(extrude2d("FPP_Blade", blade, -0.0045 * k, 0.0045 * k, "Pro_Carbon", xf=xf), 0.0015, 1, angle=30.0))
    return objs, [socket(), shape_sphere("Foot", (0.0, -0.02, 0.0), 0.07)]


# ---------------------------------------------------------------------------------------------------------------------------------
# навершия оружия (как kit_weapons: Socket в проушине, рукоять снизу, деталь растёт в −Y)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Blade_ProEnergy(base="PaintWhite"):
    """Энергоклинок (лист 1, № 04): обойма с полоской цвета игрока, кремовый блок рукояти в тёмных щеках с голубой линзой,
    кремовая гарда с огнями на концах, длинный карбоновый клинок ромбического сечения с латунным долом и голубой светящейся
    кромкой по обоим лезвиям."""
    _mats()
    b = "Base_" + base
    objs = _collar("BPE", -0.07, stripe=-0.05)
    objs.append(rbox("BPE_Hilt", (0.07, 0.088, 0.056), b, (0.0, -0.105, 0.0), 0.012, 2))
    for sx in (-1, 1):
        objs.append(rbox("BPE_Cheek", (0.012, 0.07, 0.062), "Iron", (sx * 0.037, -0.105, 0.0), 0.004, 1))
        objs.append(sphere("BPE_GuardLight", 0.008, (sx * 0.068, -0.164, 0.02), "Pro_Glow", 8, 4))
    objs += _lens("BPE_Eye", (0.0, -0.1, 0.028), (0, 0, 1), 0.014, rim="Brass", segs=12)
    guard = [(-0.086, -0.15), (-0.03, -0.14), (0.03, -0.14), (0.086, -0.15), (0.072, -0.176), (0.036, -0.187), (-0.036, -0.187),
             (-0.072, -0.176)]
    objs.append(fin(extrude2d("BPE_Guard", guard, -0.021, 0.021, b), 0.005, 2, angle=40.0))

    def section(y, hw, t):
        return [(hw, y, 0.0), (0.0, y, t), (-hw, y, 0.0), (0.0, y, -t)]

    st = [(-0.17, 0.028, 0.012), (-0.24, 0.038, 0.012), (-0.45, 0.034, 0.011), (-0.6, 0.021, 0.009), (-0.66, 0.009, 0.005)]
    objs.append(fin(loft("BPE_Blade", [section(*s) for s in st], "Pro_Carbon", pole1=(0.0, -0.7, 0.0)), angle=20.0))
    objs.append(fin(box("BPE_Fuller", (0.011, 0.36, 0.027), "Brass", (0.0, -0.38, 0.0)), 0.002, 1))
    edge = [Vector((-hw - 0.001, y, 0.0)) for y, hw, _t in st[1:]] + [Vector((0.0, -0.702, 0.0))]
    edge += [Vector((hw + 0.001, y, 0.0)) for y, hw, _t in reversed(st[1:])]
    objs.append(sweep("BPE_Edge", edge, [0.006, 0.006, 0.0055, 0.0045, 0.004, 0.0045, 0.0055, 0.006, 0.006], "Pro_Glow", sides=6))
    empties = [socket(), shape_box("Collar", (0.0, -0.03, 0.0), (0.07, 0.09, 0.07)),
               shape_box("Hilt", (0.0, -0.13, 0.0), (0.17, 0.12, 0.06)), shape_box("Blade", (0.0, -0.445, 0.0), (0.08, 0.51, 0.06))]
    return objs, empties


def build_Hammer_ProDrum(base="Brass"):
    """Молот-барабан (лист 2, № 05): обойма с полоской цвета игрока, тёмное седло и латунный барабан поперёк рукояти (Base_ —
    латунь по умолчанию, перекрашивается) в тёмных торцевых обручах, два бандажа на заклёпках; на обоих бойках — карбоновый торец
    с оранжевым светящимся кольцом и стальной бобышкой. Face_L / Face_R — бойки (на них встают моды)."""
    _mats()
    b = "Base_" + base
    yc, h = -0.165, 0.125
    ax = T((0.0, yc, 0.0)) @ Rz(-90.0)   # локальная +Y тела вращения → +X детали
    objs = _collar("HPD", -0.07, stripe=-0.05)
    objs.append(rbox("HPD_Saddle", (0.074, 0.04, 0.078), "Iron", (0.0, -0.084, 0.0), 0.01, 2))
    prof = [(0.0, -h), (0.062, -h), (0.082, -h + 0.006), (0.084, -h + 0.03), (0.086, 0.0), (0.084, h - 0.03), (0.082, h - 0.006),
            (0.062, h), (0.0, h)]
    objs.append(fin(revolve("HPD_Drum", prof, b, 24, ax), angle=40.0, uv="cyl", axis='X'))
    for s in (-1, 1):
        t = s * (h - 0.022)
        objs.append(fin(revolve("HPD_Hoop", [(0.083, t - 0.021), (0.093, t - 0.018), (0.093, t + 0.018), (0.083, t + 0.021)], "Iron", 24,
                                ax, closed=True), uv="cyl", axis='X'))
        t = s * 0.036
        objs.append(fin(revolve("HPD_Band", [(0.085, t - 0.008), (0.089, t - 0.006), (0.089, t + 0.006), (0.085, t + 0.008)], "Iron", 24,
                                ax, closed=True), uv="cyl", axis='X'))
        for k in range(3):
            a = math.radians(-50.0 + 50.0 * k)
            n = Vector((0.0, math.sin(a), math.cos(a)))
            objs.append(fin(stud("HPD_Rivet", Vector((t, yc, 0.0)) + n * 0.089, n, "Steel", 0.0065, 0.0045, 6)))
        x = s * h
        objs.append(fin(revolve("HPD_Face", [(0.0, 0.0), (0.066, 0.0), (0.066, 0.006), (0.058, 0.01), (0.0, 0.01)], "Pro_Carbon", 20,
                                align_y((s, 0, 0), (x - s * 0.002, yc, 0.0))), angle=50.0, uv="cyl", axis='X'))
        objs.append(torus("HPD_Heat", (x + s * 0.009, yc, 0.0), 0.046, 0.007, "Pro_Heat", 'YZ', 24, 5))
        objs.append(fin(stud("HPD_FaceBoss", (x + s * 0.007, yc, 0.0), (s, 0, 0), "Steel", 0.022, 0.009, 6)))
    empties = [socket(), anchor("Face_L", (h + 0.01, yc, 0.0), 90.0), anchor("Face_R", (-h - 0.01, yc, 0.0), -90.0),
               shape_box("Collar", (0.0, -0.03, 0.0), (0.072, 0.09, 0.072)), shape_cyl("Drum", (0.0, yc, 0.0), 0.09, 2 * h + 0.02, -90.0)]
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# броня
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Deco_ProPanel(base="PaintWhite", r=0.058):
    """Щит-панель на конечность (Anchor_Deco; лист 2, № 22): тёмная манжета с ремнём цвета игрока, кронштейн и перед
    конечностью — шестиугольная кремовая плита на резиновой подложке (тёмный резиновый край), два шеврона цвета игрока с болтами по углам,
    латунный узел с голубой линзой в центре; плита выгнута по конечности. r — радиус конечности (0.058 рука, 0.074 нога)."""
    _mats()
    R = r * 1.3   # манжета шире скорлуп панельной конечности (r × 1.2)
    objs = [fin(revolve("DPP_Cuff", [(R * 0.96, -0.03), (R * 1.08, -0.034), (R * 1.08, -0.07), (R * 0.96, -0.074)], "Iron", 22,
                        closed=True), 0.002, 1, uv="cyl")]
    objs.append(band("DPP_Stripe", -0.052, R * 1.1, 0.014, "Shirt_Kit"))
    zc, cy, bend = R + 0.028, -0.05 - r * 1.3, 2.0
    hw, hh = r * 1.75, r * 2.15

    def hexagon(k):
        return [(math.cos(math.pi / 6 + i * math.pi / 3) * hw * k, cy + math.sin(math.pi / 6 + i * math.pi / 3) * hh * k) for i in range(6)]

    objs.append(fin(extrude2d("DPP_Edge", hexagon(1.0), zc, zc + 0.016, "Rubber", bend=bend), 0.004, 1, angle=40.0))
    objs.append(fin(extrude2d("DPP_Plate", hexagon(0.9), zc + 0.012, zc + 0.027, "Base_" + base, bend=bend), 0.004, 1, angle=40.0))
    for half in (hexagon(0.82)[:3], hexagon(0.82)[3:]):   # шевроны цвета игрока вдоль верхних и нижних кромок плиты
        inner = [(x * 0.62 / 0.82, cy + (y - cy) * 0.62 / 0.82) for x, y in half]
        objs.append(fin(extrude2d("DPP_Chevron", half + list(reversed(inner)), zc + 0.022, zc + 0.0305, "Shirt_Kit", bend=bend),
                        0.0015, 1, angle=40.0))
    for x, y in hexagon(0.72):
        objs.append(fin(stud("DPP_Bolt", (x, y, zc + 0.0305 - bend * x * x), (2.0 * bend * x, 0.0, 1.0), "Steel", 0.0075, 0.005, 6)))
    objs += _lens("DPP_Eye", (0.0, cy, zc + 0.027), (0, 0, 1), r * 0.3, rim="Brass", segs=14)
    objs.append(fin(box("DPP_Bracket", (0.034, 0.044, zc - R + 0.014), "Iron", (0.0, -0.054, (R + zc) / 2)), 0.003, 1))
    # бокс идёт от плоскости куклы (z = 0) до плиты: формы декора должны пересекать z = 0 (kit_deco)
    return objs, [socket(), shape_box("Panel", (0.0, cy, zc / 2), (hw * 1.7, hh * 1.8, zc + 0.04))]


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3): ядро бесплатно по энергии; hit_mult — множитель удара ЭТОЙ формой (когти,
# шипы бойка, острие); у наверший энергия 0, weapon_mult работает только в крафтовом оружии; щит-панель — броня с размером S / L
# ---------------------------------------------------------------------------------------------------------------------------------
# разветвители (04.10, «невозможные конструкции»): детали со своим телом и ТРЕМЯ разъёмами под конечности — цепочка перестаёт быть
# линией. Имена якорей — из контракта (BODY_KIT.md §3.1): End (группа по цепочке) и Side_L / Side_R (группа Hip, ход −60…80°),
# поэтому builder и мастерская понимают их без правок.
# ---------------------------------------------------------------------------------------------------------------------------------
def _socket_boss(prefix, center, d, r0, r1, mat="Iron", rim="Brass"):
    """Гнездо разъёма: короткий стакан от центра узла по направлению d, r0 — от центра до начала, r1 — до торца; латунный обод."""
    xf = align_y(d, Vector(center) + Vector(d) * r0)
    h = r1 - r0
    return [fin(revolve(prefix + "_Boss", [(0.0, 0.0), (0.04, 0.0), (0.04, h - 0.01), (0.033, h), (0.0, h)], mat, 12, xf), 0.002, 1,
                uv="cyl"),
            fin(revolve(prefix + "_BossRim", [(0.041, h - 0.022), (0.045, h - 0.016), (0.041, h - 0.01)], rim, 12, xf, closed=True),
                angle=80)]


TEE_C = (0.0, -0.108, 0.0)     # центр узла тройника
TEE_D = 0.088                  # от центра до якоря
TEE_FAN = 70.0                 # боковые разъёмы — на ±70° от оси вниз


def build_Hub_ProTee(base="PaintWhite"):
    """Тройник — разветвитель про-лиги: стальная шейка с пояском цвета игрока, тёмный карбоновый шар-узел в кремовой обойме
    (две скорлупы спереди и сзади, шов открыт), спереди голубая линза; три гнезда с латунными ободами — вниз и в стороны на ±70°.
    На каждое встаёт своя конечность, кисть или навершие: одна рука расходится в три."""
    _mats()
    b = "Base_" + base
    c = Vector(TEE_C)
    R = 0.062
    objs = [fin(revolve("HPT_Stem", [(0.0, -0.036), (0.034, -0.036), (0.036, -0.058), (0.0, -0.058)], "Iron", 14), uv="cyl")]
    objs += ferrule("HPT_TopCap", -0.03, -0.05, 0.043, rivets=0)
    objs.append(band("HPT_Stripe", -0.056, 0.04, 0.011, "Shirt_Kit"))
    objs.append(fin(sphere("HPT_Ball", R, tuple(c), "Pro_Carbon", 18, 9), angle=60.0, uv="cyl"))
    # кремовая обойма: кольцо-пояс вокруг шара в плоскости кадра, спереди и сзади — щёчки
    objs.append(fin(torus("HPT_Cage", tuple(c), R + 0.004, 0.013, b, 'XY', 28, 8), angle=70.0))
    for sz in (-1, 1):
        objs.append(fin(revolve("HPT_Cheek", [(0.0, 0.0), (R * 0.62, 0.0), (R * 0.56, 0.012), (R * 0.3, 0.02), (0.0, 0.022)], b, 16,
                                align_y((0.0, 0.0, float(sz)), c + Vector((0.0, 0.0, sz * (R - 0.012))))), 0.002, 1, uv="cyl"))
    objs += _lens("HPT", c + Vector((0.0, 0.0, R + 0.008)), (0.0, 0.0, 1.0), 0.02, rim="Brass")
    empties = [socket(), shape_sphere("Hub", tuple(c), R + 0.012)]
    for nm, deg in (("End", 0.0), ("Side_L", TEE_FAN), ("Side_R", -TEE_FAN)):
        a = math.radians(deg)
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        objs += _socket_boss("HPT_" + nm, c, d, R - 0.012, TEE_D - 0.03)
        empties.append(anchor(nm, tuple(c + d * TEE_D), deg))
    return objs, empties


def build_Limb_ProSpine(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintWhite"):
    """Рама-позвонок — звено с двумя боковыми разъёмами (лист автора «рама: спортивная»): тёмная труба-рама с обоймами, посередине
    кремовое кольцо-рама в плоскости кадра на двух распорках, в нём карбоновая муфта с голубой линзой; из муфты вбок — два гнезда
    с латунными ободами. Цепочка таких звеньев — хребет: на каждом звене пара ног, рук или лезвий."""
    _mats()
    b = "Base_" + base
    ya, yb = ja * 0.6, L - jb * 0.6
    ym = -(ya + yb) / 2.0
    objs = [fin(revolve("LPS_Frame", [(0.0, -ya), (r * 0.56, -ya), (r * 0.52, -yb), (0.0, -yb)], "Iron", 14), uv="cyl")]
    objs += ferrule("LPS_TopCap", -ya + 0.012, -ya - 0.022, r * 0.96, rivets=0)
    objs += ferrule("LPS_BotCap", -yb + 0.03, -yb - 0.01, r * 0.88, rivets=0)
    objs.append(band("LPS_Stripe", -ya - 0.034, r * 0.62, 0.012, "Shirt_Kit"))
    # муфта и кольцо-рама
    hh = min(0.05, (yb - ya) * 0.24)
    objs.append(fin(revolve("LPS_Sleeve", [(r * 0.6, ym + hh), (r * 0.98, ym + hh * 0.7), (r * 0.98, ym - hh * 0.7), (r * 0.6, ym - hh)],
                            "Pro_Carbon", 16, closed=True), 0.002, 1, uv="cyl"))
    rr = min(r * 2.05, (yb - ya) * 0.5 + 0.01)
    objs.append(fin(torus("LPS_Ring", (0.0, ym, 0.0), rr, r * 0.2, b, 'XY', 30, 8), angle=70.0))
    objs += _lens("LPS", Vector((0.0, ym, r * 0.98)), (0.0, 0.0, 1.0), r * 0.3, rim="Brass")
    D = rr + 0.045
    empties = limb_empties(L, r * 1.05)
    for nm, sx in (("Side_L", 1.0), ("Side_R", -1.0)):
        d = Vector((sx, 0.0, 0.0))
        objs += _socket_boss("LPS_" + nm, (0.0, ym, 0.0), d, r * 0.9, D - 0.03)
        empties.append(anchor(nm, (sx * D, ym, 0.0), sx * 90.0))
    empties.append(shape_box("Ring", (0.0, ym, 0.0), (rr * 2.0, r * 1.2, r * 1.1)))
    return objs, empties


META = {
    "Hub_ProTee": {"kind": "joint", "title": "Тройник", "mass": 2.4, "energy": 4},
    "Limb_ProSpine": {"kind": "limb", "title": "Рама-позвонок", "mass": {"S": 2.9, "L": 5.2}, "energy": {"S": 7, "L": 9}},
    "Core_ProGyro": {"kind": "core", "title": "Ядро-гиростаб", "mass": 13.0, "energy": 0},
    "Core_ProReactor": {"kind": "core", "title": "Ядро-реактор", "mass": 16.0, "energy": 0},
    "Head_ProVisor": {"kind": "head", "title": "Голова-визор", "mass": 4.2, "energy": 9},
    "Head_ProPilot": {"kind": "head", "title": "Шлем пилота", "mass": 4.6, "energy": 10},
    "Limb_ProPanel": {"kind": "limb", "title": "Панельная", "mass": {"S": 2.6, "L": 5.0}, "energy": {"S": 6, "L": 8}},
    "Hand_ProClaw": {"kind": "hand", "title": "Клешня про", "mass": 1.1, "energy": 4, "hit_mult": 1.15},
    "Hand_ProCrusher": {"kind": "hand", "title": "Дробилка", "mass": 1.9, "energy": 5, "hit_mult": 1.2},
    "Blade_ProEnergy": {"kind": "weapon_head", "title": "Энергоклинок", "mass": 1.2, "energy": 0, "weapon_mult": 1.55,
                        "name_prefix": "Blade"},
    "Hammer_ProDrum": {"kind": "weapon_head", "title": "Молот-барабан", "mass": 3.4, "energy": 0, "weapon_mult": 1.4,
                       "name_prefix": "Hammer"},
    "Foot_ProWheel": {"kind": "foot", "title": "Большое колесо", "mass": 1.2, "energy": 4},
    "Foot_ProSpike": {"kind": "foot", "title": "Стопа-копьё", "mass": 0.8, "energy": 3, "hit_mult": 1.2},
    "Foot_ProProp": {"kind": "foot", "title": "Стопа-пропеллер", "mass": 0.9, "energy": 4},
    "Deco_ProPanel": {"kind": "armor", "title": "Щит-панель", "mass": {"S": 1.3, "L": 1.9}, "energy": 4},
}
