"""Детали NULL League — части других цивилизаций лиги (листы автора «NULL League parts» / «Extraterrestrial parts», 30.09.2026;
описание — docs/plan-demo/ART_NULL.md, листы 3–4; лор — правило трофея, LORE_NULL.md).

v2 (30.09, отзыв автора «выглядят как обычные»): у v1 чужими были только акценты, а корпуса — ржавое железо и кремовая краска кита,
шары-шарниры и пояски цвета игрока, лицо-карточка. Теперь у деталей свой язык, общий для всей лиги:
  • корпус — пустотный металл (почти чёрный глянец с фиолетовым отливом) или живая ткань (тёмно-алая) с хитином;
  • свет — фиолетовые швы, кромки и узлы поля, голубые сенсоры, энергокристалл;
  • «парящий» шарнир — у сокета каждой конечности, кисти и стопы светящееся кольцо вокруг шара сустава, сам сегмент шара не
    касается (зазор, как «floating connection» на листе);
  • Base_<Mat> (ось материалов: физика и перекраска в мастерской) — только отделка: латунные эмиттеры, рамы, когти, костяные
    шипы; корпус чужой детали не перекрашивается;
  • нечеловеческие детали: щупальце, клешня, ходуля-коготь, парящая стопа, кристальное и живое ядро, живая голова.

Контракт — как у остального кита (docs/plan-demo/BODY_KIT.md): стандартные сокеты и якоря, у голов FacePlate (фото игрока — за
визором), у ядер Shirt_Kit (у лиги — парящее кольцо, а не крашеный пояс). Роли League_* не перекрашиваются, .tres пишет
tools/build_league.gd:
    League_Void     пустотный металл — корпуса, рамы, лезвия, хитин
    League_Glow     фиолетовое свечение поля — кольца суставов, швы, глаза, кромки
    League_Cyan     голубое свечение — сенсоры, прожилки кристаллов
    League_Crystal  энергокристалл — полупрозрачный голубой с внутренним светом
    League_Gold     гармонический металл — кольца, которые не должны перекрашиваться
    League_Flesh    живая ткань — тёмно-алая, влажный блеск
Удар формой (WORKSHOP_V3.md §4, ≤ ×1.2): коса ×1.2 и когти / ходуля ×1.15 — колющие (бонус на медленном тычке), клешня и
кристальная конечность ×1.1 — дробящие (на размахе), щупальце ×0.9 — мягкое; профиль — HIT_PROFILE tools/build_body_kit.gd, число —
META hit_mult (= HIT_MULT tests/kit_probe.gd). Особые механики (гравиядро, щит, фаза, самопочинка) — активные модули
(kit_active.py, scripts/active/) и пассивы ядер лиги (ActiveBlocks.PASSIVE).
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
    "League_Void": ((0.028, 0.022, 0.045, 1.0), 0.2, 0.75, None, 0.0, 1.0),
    "League_Glow": ((0.3, 0.05, 0.65, 1.0), 0.3, 0.0, (0.45, 0.06, 1.0), 1.1, 1.0),
    "League_Cyan": ((0.08, 0.35, 0.5, 1.0), 0.3, 0.0, (0.15, 0.75, 1.0), 1.4, 1.0),
    "League_Crystal": ((0.35, 0.72, 0.95, 1.0), 0.05, 0.0, (0.2, 0.6, 1.0), 1.0, 0.55),
    "League_Gold": ((0.85, 0.58, 0.2, 1.0), 0.28, 0.9, None, 0.0, 1.0),
    "League_Flesh": ((0.26, 0.018, 0.035, 1.0), 0.32, 0.0, (0.35, 0.02, 0.06), 0.25, 1.0),
}
GLOW_R = 0.86  # радиус кольца сустава / радиус шара коннектора (JOINT_R): у бойца лиги шар ужат — кольцо видно вокруг него
## Сегмент начинается на доле радиуса шара от центра сустава: у бойца лиги шар коннектора ужат (LEAGUE_JOINT_SCALE) — между
## ним и сегментом зазор («парящий» сустав); на обычном бойце кита (трофей) полный шар закрывает торец, как у деталей кита.
SEG_GAP = 0.86
LEAGUE_JOINT_SCALE = 0.55   # = LeagueLook.JOINT_SCALE (scripts/league/league_look.gd)


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


# ---------------------------------------------------------------------------------------------------------------------------------
# общие узлы языка лиги
# ---------------------------------------------------------------------------------------------------------------------------------
def _shard(name, base_pos, direction, length, radius, mat, sides=6, taper=0.55, twist=0.0):
    """Кристалл: n-гранная призма от base_pos по direction, сужается (taper) и сходится в острие."""
    d = Vector(direction).normalized()
    xf = align_y(d, base_pos)
    rings = []
    for t, rr in ((0.0, radius * 0.8), (0.08, radius), (0.7, radius * taper)):
        y = length * t
        rings.append([tuple(xf @ Vector((rr * math.cos(2 * math.pi * i / sides + twist * t), y, rr * math.sin(2 * math.pi * i / sides + twist * t))))
                      for i in range(sides)])
    tip = tuple(xf @ Vector((0.0, length, 0.0)))
    return loft(name, rings, mat, caps=True, pole1=tip)


def _joint_ring(prefix, y, jr, mat="League_Glow"):
    """«Парящий» сустав: тонкое светящееся кольцо в плоскости кадра вокруг шара коннектора (радиус шара по JOINT_R — jr)."""
    return [torus(prefix + "_JRing", (0.0, y, 0.0), jr * GLOW_R, 0.0036, mat, 'XY', 28, 5)]


def _spindle(name, y0, y1, rmax, mat="League_Void", sides=8, peak=0.35, r_top=0.45, r_bot=0.4):
    """Гранёное веретено от y0 вниз до y1 (y0 > y1): самое толстое на доле peak, торцы сужены — сегмент «парит» между шарами."""
    L = y0 - y1
    prof = [(0.0, y0), (rmax * r_top, y0), (rmax * 0.82, y0 - L * peak * 0.45), (rmax, y0 - L * peak),
            (rmax * 0.78, y0 - L * (peak + (1 - peak) * 0.55)), (rmax * r_bot, y1), (0.0, y1)]
    return fin(revolve(name, prof, mat, sides, phase=0.0), 0.0, angle=25.0, uv="cyl"), prof


def _prof_r(prof, y):
    """Радиус профиля revolve на высоте y (линейно между точками)."""
    for (ra, ya), (rb, yb) in zip(prof, prof[1:]):
        if min(ya, yb) <= y <= max(ya, yb) and abs(ya - yb) > 1e-9:
            return ra + (rb - ra) * (y - ya) / (yb - ya)
    return 0.0


def _seam(name, prof, y0, y1, angle_deg=90.0, r=0.0032, n=12, mat="League_Glow", sides=8):
    """Светящийся шов по ребру веретена (угол ребра в плоскости XZ; 90° — ребро к камере при sides = 8 и 4)."""
    a = math.radians(angle_deg)
    pts = []
    for i in range(n + 1):
        y = y0 + (y1 - y0) * i / n
        rr = _prof_r(prof, y)
        pts.append(Vector((rr * math.cos(a), y, rr * math.sin(a))))
    return sweep(name, pts, r, mat, sides=5)


def _emitter(prefix, y, r, mat, down=True):
    """Латунный эмиттер поля на торце сегмента (Base_ — отделка на оси материалов): короткая чашка с фаской."""
    h = 0.018 if down else -0.018
    prof = [(0.0, y), (r * 0.7, y), (r, y - h * 0.3), (r, y - h), (r * 0.8, y - h * 1.1), (0.0, y - h * 1.1)]
    return fin(revolve(prefix + "_Emit", prof, mat, 16), 0.001, 1, uv="cyl")


def _neck(prefix):
    """Шейка головы лиги: тёмная, с кольцом сустава вокруг шара шеи (Neck 0.05)."""
    objs = [fin(revolve(prefix + "_Neck", [(0.0, 0.03), (0.026, 0.03), (0.03, 0.05), (0.056, 0.064), (0.056, 0.072), (0.0, 0.072)],
                        "League_Void", 18), 0.002, 1, uv="cyl")]
    return objs + _joint_ring(prefix, 0.0, 0.05)


def _bosses(prefix, R, anchors, mat="League_Void", ring="League_Glow"):
    """Гнёзда-бобышки на якорях шара-ядра (как Core_Ball): (имя, угол в XY, расстояние якоря)."""
    objs, empties = [], []
    for nm, deg, dist in anchors:
        d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))
        h = 0.03 + (dist - 0.262)
        objs.append(fin(revolve(prefix + "_Boss", [(0.0, 0.0), (0.045, 0.0), (0.045, h - 0.012), (0.036, h), (0.0, h)], mat, 12,
                                align_y(d, d * (R - 0.012))), 0.003, 1, uv="cyl"))
        objs.append(fin(revolve(prefix + "_BossRing", [(0.048, h - 0.026), (0.05, h - 0.02), (0.048, h - 0.014)], ring, 12,
                                align_y(d, d * (R - 0.012)), closed=True), angle=80))
        empties.append(anchor(nm, tuple(d * dist), _rot(nm)))
    return objs, empties


def _float_band(prefix, y, rad, minor=0.018):
    """Цвет игрока у ядра лиги: парящее кольцо (Shirt_Kit) вокруг корпуса, а не крашеный пояс. Горизонтальное: сбоку читается
    полосой через весь корпус. Два тонких светящихся кольца по кромкам — поле, которое его держит."""
    return [fin(torus(prefix + "_PlayerBand", (0.0, y, 0.0), rad, minor, "Shirt_Kit", 'XZ', 36, 6), angle=80),
            torus(prefix + "_BandGlowT", (0.0, y + minor * 1.15, 0.0), rad - 0.004, 0.0035, "League_Glow", 'XZ', 36, 4),
            torus(prefix + "_BandGlowB", (0.0, y - minor * 1.15, 0.0), rad - 0.004, 0.0035, "League_Glow", 'XZ', 36, 4)]


def _bezier3(a, b, c, d, n):
    a, b, c, d = Vector(a), Vector(b), Vector(c), Vector(d)
    return [a * (1 - t) ** 3 + b * 3 * (1 - t) ** 2 * t + c * 3 * (1 - t) * t * t + d * t ** 3 for t in (i / n for i in range(n + 1))]


def _horn(name, pts, r0, mat="League_Void", sides=7, tip=None):
    """Рог / коготь / шип по кривой: сужение к острию; tip — материал светящегося кончика (сфера)."""
    n = len(pts)
    radii = [r0 * (1.0 - i / (n - 1)) ** 0.8 + 0.0015 for i in range(n)]
    out = [fin(sweep(name, pts, radii, mat, sides=sides), angle=50)]
    if tip:
        out.append(sphere(name + "Tip", max(r0 * 0.28, 0.004), tuple(pts[-1]), tip, 8, 4))
    return out


BALL_ANCHORS = [("Neck", 90.0, 0.262), ("Shoulder_L", 46.4, 0.283), ("Shoulder_R", 133.6, 0.283), ("Side_L", -5.0, 0.262),
                ("Side_R", 185.0, 0.262), ("Hip_L", -62.0, 0.262), ("Hip_R", -118.0, 0.262)]


# ---------------------------------------------------------------------------------------------------------------------------------
# головы: FacePlate — фото игрока за визором (правило вещания: табло показывает лицо, LORE_NULL.md)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Head_LeagueEye(base="Brass"):
    """Голова-око: вытянутое назад чёрное яйцо с огромным объективом (фото игрока — в линзе за фиолетовым кольцом), два длинных
    рога-сенсора назад и вверх со светящимися кончиками, гребень из трёх плавников по макушке."""
    _mats()
    prof = [(0.0, 0.06), (0.07, 0.066), (0.118, 0.1), (0.145, 0.16), (0.15, 0.22), (0.14, 0.29), (0.112, 0.35), (0.07, 0.39),
            (0.03, 0.405), (0.0, 0.408)]
    shell = revolve("HLE_Shell", prof, "League_Void", 24)
    cut_sphere(shell, (0.0, 0.225, 0.2), 0.1, 28)
    objs = [fin(shell, 0.0, angle=40.0, uv="cyl")]
    objs.append(fin(torus("HLE_Bezel", (0.0, 0.225, 0.128), 0.082, 0.014, "Base_" + base, 'XY', 32, 7), angle=80))
    objs.append(torus("HLE_Iris", (0.0, 0.225, 0.13), 0.066, 0.0065, "League_Glow", 'XY', 32, 5))
    objs.append(torus("HLE_IrisIn", (0.0, 0.225, 0.118), 0.058, 0.0035, "League_Cyan", 'XY', 32, 4))
    for sx in (-1, 1):
        root = Vector((sx * 0.11, 0.31, -0.05))
        pts = _bezier3(root, root + Vector((sx * 0.06, 0.07, -0.05)), root + Vector((sx * 0.1, 0.16, -0.14)),
                       root + Vector((sx * 0.07, 0.26, -0.24)), 12)
        objs += _horn("HLE_Horn", pts, 0.026, sides=6, tip="League_Glow")
        objs.append(sphere("HLE_Sense", 0.011, (sx * 0.143, 0.2, 0.05), "League_Cyan", 10, 5))
    for k, (y, z, h) in enumerate(((0.405, 0.02, 0.07), (0.39, -0.07, 0.085), (0.35, -0.13, 0.07))):
        xf = T((0.0, y - 0.01, z)) @ Rx(-25.0 - k * 22.0) @ Matrix.Rotation(math.radians(90.0), 4, 'Y')
        objs.append(fin(extrude2d("HLE_Crest", [(-0.035, 0.0), (0.03, 0.0), (0.02, h * 0.6), (-0.03, h)], -0.004, 0.004, "League_Void",
                                  xf=xf), 0.0015, 1, angle=40.0))
    objs += _neck("HLE")
    face = face_plate("FacePlate", (0.0, 0.225, 0.109), 0.116, 0.116, cols=8, rows=8, round_n=2.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.42, 0.0), 180.0), shape_sphere("Head", (0.0, 0.225, 0.0), 0.16)]
    return objs, empties, [face]


def build_Head_LeagueCrystal(base="Brass"):
    """Кристальная голова: чёрная маска с узким визором в латунной раме (фото — за визором), из маски растёт косая друза
    энергокристаллов (главный наклонён назад, четыре боковых), в основании светится голубое ядро."""
    _mats()
    mask = rbox("HLK_Mask", (0.25, 0.19, 0.22), "League_Void", (0.0, 0.14, 0.0), 0.05, 3)
    cut_box(mask, (0.0, 0.14, 0.115), (0.18, 0.1, 0.04))
    objs = [fin(mask, 0.0, angle=35.0)]
    objs.append(rounded_frame("HLK_Frame", (0.0, 0.14), 0.094, 0.054, 0.008, "Base_" + base, 0.106))
    objs.append(fin(box("HLK_Brow", (0.26, 0.022, 0.05), "League_Void", (0.0, 0.205, 0.1)), 0.006, 2))
    objs.append(box("HLK_BrowGlow", (0.2, 0.005, 0.012), "League_Glow", (0.0, 0.195, 0.126)))
    objs.append(fin(_shard("HLK_Main", (0.01, 0.22, -0.01), (0.12, 1.0, -0.28), 0.38, 0.08, "League_Crystal", twist=0.5), angle=20.0))
    for sx, lean, ln, rr in ((-1, 0.8, 0.2, 0.04), (1, 0.7, 0.24, 0.045), (-1, 0.35, 0.27, 0.05), (1, 1.4, 0.13, 0.03)):
        objs.append(fin(_shard("HLK_Side", (sx * 0.06, 0.225, 0.0), (sx * lean, 1.0, -0.15), ln, rr, "League_Crystal"), angle=20.0))
    objs.append(sphere("HLK_Core", 0.04, (0.0, 0.26, -0.01), "League_Cyan", 12, 6))
    objs += _neck("HLK")
    face = face_plate("FacePlate", (0.0, 0.14, 0.097), 0.175, 0.096, cols=10, rows=6, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.58, 0.0), 180.0), shape_box("Head", (0.0, 0.2, 0.0), (0.25, 0.36, 0.22))]
    return objs, empties, [face]


def build_Head_LeagueRing(base="Brass"):
    """Голова-портал: чёрная сфера с окном под фото в латунной раме, вокруг неё в плоскости кадра — большое кольцо-портал со
    светящейся внутренней кромкой и четырьмя узлами; кольцо держат две стойки от висков."""
    _mats()
    c = Vector((0.0, 0.2, 0.0))
    shell = sphere("HLR_Shell", 0.14, tuple(c), "League_Void", 22, 11)
    cut_box(shell, (0.0, 0.2, 0.155), (0.19, 0.15, 0.06))
    objs = [fin(shell, 0.0, angle=50.0, uv="cyl")]
    objs.append(rounded_frame("HLR_Frame", (0.0, 0.2), 0.09, 0.07, 0.009, "Base_" + base, 0.126))
    ring_c = c + Vector((0.0, 0.02, -0.06))
    R = 0.25
    objs.append(fin(torus("HLR_Portal", tuple(ring_c), R, 0.02, "League_Void", 'XY', 40, 5), angle=60))
    objs.append(torus("HLR_PortalGlow", tuple(ring_c + Vector((0.0, 0.0, 0.004))), R - 0.02, 0.006, "League_Glow", 'XY', 40, 4))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        p = ring_c + Vector((R * math.cos(a), R * math.sin(a), 0.012))
        objs.append(fin(sphere("HLR_Node", 0.026, tuple(p), "League_Void", 10, 5), angle=80))
        objs.append(sphere("HLR_NodeGlow", 0.014, tuple(p + Vector((0.0, 0.0, 0.018))), "League_Cyan", 8, 4))
    for sx in (-1, 1):
        a0 = c + Vector((sx * 0.12, 0.0, -0.04))
        a1 = ring_c + Vector((sx * (R - 0.018), 0.0, 0.0))
        objs.append(fin(sweep("HLR_Strut", [a0, a0.lerp(a1, 0.5) + Vector((0.0, 0.012, -0.01)), a1], 0.011, "League_Void", sides=6),
                        angle=60))
        objs.append(fin(sphere("HLR_Temple", 0.03, tuple(a0), "Base_" + base, 10, 5), angle=80))
    objs += _neck("HLR")
    face = face_plate("FacePlate", (0.0, 0.2, 0.127), 0.168, 0.128, cols=8, rows=6, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.47, 0.0), 180.0), shape_sphere("Head", tuple(c), 0.15)]
    return objs, empties, [face]


def build_Head_LeagueFlesh(base="Bone"):
    """Живая голова: тёмно-алая луковица под тремя хитиновыми пластинами, гроздь из пяти светящихся глаз разного размера, внизу —
    окно-перепонка под фото между двумя костяными жвалами (Base_ — кость, перекрашивается)."""
    _mats()
    prof = [(0.0, 0.06), (0.06, 0.064), (0.11, 0.1), (0.14, 0.16), (0.15, 0.22), (0.14, 0.28), (0.11, 0.33), (0.06, 0.37), (0.0, 0.38)]
    bulb = revolve("HLF_Bulb", prof, "League_Flesh", 24)
    for v in bulb.data.vertices:   # бугры: радиальная рябь, живая ткань не бывает ровной
        co = v.co
        k = 1.0 + 0.045 * math.sin(co.x * 60.0) * math.sin(co.z * 45.0 + co.y * 30.0)
        v.co = (co.x * k, co.y * k, co.z)
    objs = [fin(bulb, 0.0, angle=60.0, uv="cyl")]
    for k, (y, tilt, w) in enumerate(((0.33, 30.0, 0.24), (0.37, 5.0, 0.2), (0.35, -30.0, 0.22))):
        pts = [(-w / 2, 0.0), (-w * 0.3, 0.035), (0.0, 0.045), (w * 0.3, 0.035), (w / 2, 0.0), (w * 0.3, 0.01), (0.0, 0.016), (-w * 0.3, 0.01)]
        xf = T((0.0, y - 0.02, 0.03 - k * 0.07)) @ Rx(-tilt - 60.0)
        objs.append(fin(extrude2d("HLF_Plate", pts, -0.006, 0.006, "League_Void", bend=3.0, xf=xf), 0.002, 1, angle=40.0))
    for x, y, r in ((-0.04, 0.26, 0.034), (0.045, 0.28, 0.024), (0.075, 0.225, 0.016), (-0.085, 0.21, 0.015), (0.01, 0.315, 0.013)):
        z = math.sqrt(max(0.145 ** 2 - x * x - (y - 0.22) ** 2 * 0.6, 0.0))
        objs.append(fin(sphere("HLF_Socket", r * 1.35, (x, y, z - r * 0.35), "League_Void", 10, 5), angle=80))
        objs.append(sphere("HLF_Eye", r, (x, y, z + r * 0.2), "League_Glow", 12, 6))
    for sx in (-1, 1):
        pts = _bezier3((sx * 0.08, 0.14, 0.1), (sx * 0.12, 0.08, 0.14), (sx * 0.09, 0.0, 0.16), (sx * 0.03, -0.03, 0.15), 10)
        objs += _horn("HLF_Mandible", pts, 0.022, "Base_" + base, sides=6)
    objs.append(fin(revolve("HLF_Neck", [(0.0, 0.03), (0.03, 0.03), (0.04, 0.05), (0.062, 0.07), (0.0, 0.075)], "League_Flesh", 16),
                    0.0, angle=60.0, uv="cyl"))
    objs += _joint_ring("HLF", 0.0, 0.05)
    face = face_plate("FacePlate", (0.0, 0.14, 0.133), 0.11, 0.07, bend=1.2, cols=8, rows=5, round_n=3.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.4, 0.0), 180.0), shape_sphere("Head", (0.0, 0.215, 0.0), 0.155)]
    return objs, empties, [face]


# ---------------------------------------------------------------------------------------------------------------------------------
# ядра
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Core_LeagueOrb(base="Brass"):
    """Ядро-око: чёрный шар с огромным фиолетовым глазом-щелью в латунной обойме, над ним кольцо-стабилизатор с голубыми узлами,
    цвет игрока — парящее кольцо под глазом, два спинных плавника."""
    _mats()
    R = 0.2
    objs = [fin(sphere("CLO_Ball", R, (0, 0, 0), "League_Void", 28, 14), angle=60.0, uv="cyl")]
    eye = align_y((0, 0, 1), (0.0, 0.03, 0.0))
    objs.append(fin(revolve("CLO_Bezel", [(0.115, 0.15), (0.125, 0.172), (0.11, 0.196), (0.088, 0.203), (0.08, 0.19)], "Base_" + base, 28,
                            eye, closed=True), 0.002, 1, uv="cyl"))
    objs.append(revolve("CLO_Iris", [(0.09, 0.184), (0.07, 0.196), (0.035, 0.204), (0.0, 0.206)], "League_Glow", 28, eye))
    objs.append(fin(box("CLO_Pupil", (0.016, 0.1, 0.012), "League_Void", (0.0, 0.03, 0.207)), 0.005, 2))
    ry = 0.14
    rr = math.sqrt(R * R - ry * ry) + 0.03
    objs.append(fin(torus("CLO_Ring", (0.0, ry, 0.0), rr, 0.01, "League_Gold", 'XZ', 32, 6), angle=80))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        objs.append(sphere("CLO_RingNode", 0.016, (rr * math.cos(a), ry, rr * math.sin(a)), "League_Cyan", 8, 4))
    objs += _float_band("CLO", -0.115, math.sqrt(R * R - 0.115 ** 2) + 0.03)
    for sx in (-1, 1):
        pts = [(0.0, 0.0), (0.03, 0.0), (0.012, 0.12), (-0.02, 0.1)]
        xf = T((sx * 0.06, 0.13, -0.12)) @ Rx(-35.0) @ Matrix.Rotation(math.radians(90.0 + sx * 20.0), 4, 'Y')
        objs.append(fin(extrude2d("CLO_Fin", pts, -0.005, 0.005, "League_Void", xf=xf), 0.002, 1, angle=40.0))
    bo, empties = _bosses("CLO", R, BALL_ANCHORS)
    objs += bo
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


def build_Core_LeagueGyro(base="Brass"):
    """Ядро-гироскоп: чёрный шар с голубым светящимся швом, вокруг два латунных карданных кольца (Base_ — перекрашиваются; спереди
    читаются крестом) с фиолетовыми узлами, цвет игрока — парящее кольцо внизу."""
    _mats()
    R = 0.18
    objs = [fin(sphere("CLG_Ball", R, (0, 0, 0), "League_Void", 24, 12), angle=60.0, uv="cyl")]
    objs.append(torus("CLG_Seam", (0.0, 0.0, 0.0), R + 0.002, 0.006, "League_Cyan", 'XZ', 32, 4))
    objs.append(torus("CLG_SeamV", (0.0, 0.0, 0.0), R + 0.002, 0.005, "League_Cyan", 'XY', 32, 4))
    objs.append(fin(torus("CLG_RingV", (0.0, 0.0, 0.0), 0.25, 0.014, "Base_" + base, 'YZ', 36, 6), angle=80))
    objs.append(fin(torus("CLG_RingH", (0.0, 0.03, 0.0), 0.33, 0.014, "Base_" + base, 'XZ', 44, 6), angle=80))
    for sz in (-1, 1):   # оси подвеса вертикального кольца
        objs.append(fin(revolve("CLG_Pivot", [(0.018, 0.0), (0.018, 0.07), (0.0, 0.075)], "League_Void", 12,
                                align_y((0, 0, sz), (0.0, 0.0, sz * (R - 0.01)))), 0.002, 1, uv="cyl"))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        objs.append(sphere("CLG_Node", 0.02, (0.33 * math.cos(a), 0.03, 0.33 * math.sin(a)), "League_Glow", 8, 4))
    objs += _float_band("CLG", -0.1, math.sqrt(R * R - 0.1 ** 2) + 0.028)
    anchors = [("Neck", 90.0, 0.242), ("Shoulder_L", 44.0, 0.262), ("Shoulder_R", 136.0, 0.262), ("Side_L", -5.0, 0.242),
               ("Side_R", 185.0, 0.242), ("Hip_L", -62.0, 0.242), ("Hip_R", -118.0, 0.242)]
    bo, empties = _bosses("CLG", R, [(n, a, d + 0.02) for n, a, d in anchors])
    objs += bo
    empties.append(anchor("Back", (0.0, 0.12, -0.13), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


def build_Core_LeagueCrystal(base="Brass"):
    """Кристальное ядро: друза энергокристаллов (главный столб, шесть косых) в чёрной клетке-рамке с латунными углами (Base_),
    внутри светится голубое сердце; цвет игрока — парящее кольцо по поясу рамки; гнёзда суставов — на рамке."""
    _mats()
    objs = []
    for sy in (-1, 1):   # верхняя и нижняя плиты рамки
        objs.append(fin(rbox("CLK_Plate", (0.34, 0.036, 0.26), "League_Void", (0.0, sy * 0.2, 0.0), 0.014, 2), angle=35.0))
        objs.append(box("CLK_PlateGlow", (0.3, 0.006, 0.006), "League_Glow", (0.0, sy * 0.2, 0.131)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            objs.append(fin(box("CLK_Bar", (0.026, 0.37, 0.026), "League_Void", (sx * 0.15, 0.0, sz * 0.11)), 0.006, 1))
            for sy in (-1, 1):
                objs.append(fin(sphere("CLK_Corner", 0.03, (sx * 0.16, sy * 0.2, sz * 0.12), "Base_" + base, 12, 6), angle=80))
    objs.append(fin(_shard("CLK_Main", (0.0, -0.17, 0.0), (0.0, 1.0, 0.0), 0.36, 0.075, "League_Crystal", sides=6, taper=0.75,
                           twist=0.3), angle=20.0))
    for k, (dx, dz, ln, rr) in enumerate(((0.9, 0.3, 0.17, 0.04), (-0.8, 0.4, 0.19, 0.045), (0.6, -0.5, 0.15, 0.035),
                                          (-0.5, -0.6, 0.16, 0.04), (0.2, 0.9, 0.13, 0.035), (-1.0, -0.1, 0.12, 0.03))):
        objs.append(fin(_shard("CLK_Side", (0.0, -0.1 + 0.03 * k, 0.0), (dx, 0.9, dz), ln, rr, "League_Crystal", sides=5), angle=20.0))
    objs.append(sphere("CLK_Heart", 0.045, (0.0, 0.0, 0.0), "League_Cyan", 14, 7))
    objs += _float_band("CLK", -0.05, 0.215, 0.016)
    pos = {"Neck": (0.0, 0.25, 0.0), "Shoulder_L": (0.22, 0.19, 0.0), "Side_L": (0.225, -0.02, 0.0), "Hip_L": (0.11, -0.255, 0.0)}
    empties = []
    for nm, p in list(pos.items()) + [(n.replace("_L", "_R"), (-p[0], p[1], p[2])) for n, p in pos.items() if n.endswith("_L")]:
        p = Vector(p)
        d = p.normalized()
        root = p - d * 0.055
        objs.append(fin(revolve("CLK_Boss", [(0.0, 0.0), (0.04, 0.0), (0.04, 0.03), (0.032, 0.04), (0.0, 0.04)], "League_Void", 14,
                                align_y(d, root)), 0.002, 1, uv="cyl"))
        empties.append(anchor(nm, tuple(p), _rot(nm)))
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_box("Torso", (0, 0, 0), (0.34, 0.44, 0.26)))
    return objs, empties


def build_Core_LeagueFlesh(base="Bone"):
    """Живое ядро: ребристый тёмно-алый мешок под хитиновым панцирем спереди, светящиеся фиолетовые прожилки и пятна, гребень
    костяных шипов по спине (Base_ — кость); цвет игрока — перетяжка-перепонка по низу."""
    _mats()
    R = 0.2

    def rad(y):
        t = max(-1.0, min(1.0, y / (R * 1.1)))
        return R * math.sqrt(max(1.0 - t * t, 0.0)) * (1.0 + 0.06 * math.sin(y * 70.0))

    prof = [(0.0, -R * 1.1)] + [(rad(-R * 1.1 + 2.2 * R * k / 18), -R * 1.1 + 2.2 * R * k / 18) for k in range(1, 18)] + [(0.0, R * 1.1)]
    objs = [fin(revolve("CLF_Sac", prof, "League_Flesh", 28), 0.0, angle=60.0, uv="cyl")]
    # хитиновый панцирь: тёмная шапка на верхней половине мешка с тремя гребнями, по кромке — светящийся шов
    cap = [(0.0, R * 1.1 + 0.014)] + [(rad(y) + 0.014, y) for y in (R * 0.95, R * 0.75, R * 0.5, R * 0.25)] + [
        (rad(0.03) + 0.018, 0.03), (rad(0.03) + 0.004, 0.02)]
    objs.append(fin(revolve("CLF_Cap", cap, "League_Void", 28), 0.0, angle=40.0, uv="cyl"))
    objs.append(torus("CLF_CapGlow", (0.0, 0.026, 0.0), rad(0.03) + 0.012, 0.0045, "League_Glow", 'XZ', 40, 5))
    for k, a in enumerate((-0.5, 0.0, 0.5)):   # гребни по панцирю спереди назад
        pts = [Vector((math.sin(a) * (rad(y) + 0.016), y, math.cos(a) * (rad(y) + 0.016))) for y in (0.05, 0.1, 0.15, 0.19)]
        pts.append(Vector((0.0, R * 1.1 + 0.016, 0.0)).lerp(pts[-1], 0.35))
        objs.append(fin(sweep("CLF_Ridge", pts, [0.012, 0.014, 0.013, 0.01, 0.006], "League_Void", sides=5), angle=40))
    for sx in (-1, 1):
        pts = [Vector((sx * rad(y) * 0.92 * math.cos(0.5), y, rad(y) * 0.92 * math.sin(0.5) * 0.6)) for y in
               (0.0, -0.035, -0.07, -0.1, -0.12)]
        pts = [Vector((p.x, p.y, math.sqrt(max(rad(p.y) ** 2 - p.x ** 2, 0.0)) + 0.002)) for p in pts]
        objs.append(sweep("CLF_Vein", pts, 0.0045, "League_Glow", sides=5))
    for x, y in ((0.12, -0.1), (-0.13, -0.06), (0.05, -0.04), (-0.05, -0.11)):
        z = math.sqrt(max(rad(y) ** 2 - x * x, 0.0))
        objs.append(sphere("CLF_Spot", 0.012, (x, y, z), "League_Glow", 10, 5))
    for k in range(5):   # спинной гребень: от макушки назад и вниз, шипы наклонены назад
        th = math.radians(8.0 + k * 22.0)
        nrm = Vector((0.0, math.cos(th), -math.sin(th)))
        p = nrm * (R * 1.1 + 0.005)
        d = (nrm + Vector((0.0, 0.0, -0.45))).normalized()
        objs.append(fin(spike("CLF_Spine", tuple(p), tuple(d), 0.1 - 0.012 * k, 0.024, "Base_" + base, 8), angle=50.0))
    objs.append(_player_band("CLF_PlayerBand", -0.13, -0.19, lambda y: rad(y), lift=0.006, segs=28, steps=3))
    bo, empties = _bosses("CLF", R, BALL_ANCHORS, mat="League_Flesh", ring="League_Void")
    objs += bo
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# конечности (L, r, ja, jb — как у kit_limbs; размеры S / L даёт body_kit.sized). Сегмент от −ja до −L + jb — «парит» между шарами
# ---------------------------------------------------------------------------------------------------------------------------------
def _float_limb(prefix, L, r, ja, jb, base, rmax_k=0.85, peak=0.35):
    """Общий каркас конечности лиги: кольцо сустава у сокета, латунные эмиттеры на торцах, гранёное чёрное веретено, шов к камере."""
    y0, y1 = -ja * SEG_GAP - 0.016, -L + jb * SEG_GAP + 0.016
    objs = _joint_ring(prefix, 0.0, ja)
    objs.append(_emitter(prefix + "T", -ja * SEG_GAP, r * 0.5, "Base_" + base))
    objs.append(_emitter(prefix + "B", -L + jb * SEG_GAP, r * 0.45, "Base_" + base, down=False))
    sp, prof = _spindle(prefix + "_Body", y0, y1, r * rmax_k, peak=peak)
    objs.append(sp)
    objs.append(_seam(prefix + "_Seam", prof, y0 - (y0 - y1) * 0.12, y0 - (y0 - y1) * 0.82))
    return objs, prof, y0, y1


def build_Limb_LeagueFloat(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Brass"):
    """Парящая: гранёное чёрное веретено между двумя латунными эмиттерами, светящийся шов к камере, у сокета — кольцо поля вокруг
    шара сустава (сегмент шаров не касается)."""
    _mats()
    objs, prof, y0, y1 = _float_limb("LLF", L, r, ja, jb, base)
    ym = y0 - (y0 - y1) * 0.35
    for sx in (-1, 1):   # боковые рёбра-плавники в плоскости кадра: силуэт шире, чем труба
        rr = _prof_r(prof, ym)
        pts = [(sx * rr * 0.9, ym + 0.06), (sx * (rr + 0.022), ym), (sx * rr * 0.9, ym - 0.1)]
        objs.append(fin(extrude2d("LLF_Rib", pts if sx > 0 else list(reversed(pts)), -0.006, 0.006, "League_Void"), 0.0015, 1, angle=30))
    return objs, limb_empties(L, r * 0.8)


def build_Limb_LeagueCrystal(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Brass"):
    """Кристальная: шестигранный энергокристалл парит между двумя чёрными держателями с латунными кромками, внутри голубая
    прожилка; у сокета — кольцо сустава."""
    _mats()
    ya, yb = ja * SEG_GAP, L - jb * SEG_GAP
    objs = _joint_ring("LLC", 0.0, ja)
    for nm, yt, yb_, rr in (("LLC_Top", -ya, -ya - 0.034, r * 0.8), ("LLC_Bot", -yb + 0.03, -yb, r * 0.72)):
        objs.append(fin(revolve(nm, [(0.0, yt), (rr * 0.7, yt), (rr, yt - 0.008), (rr, yb_ + 0.008), (rr * 0.7, yb_), (0.0, yb_)],
                                "League_Void", 6, phase=math.pi / 6), 0.002, 1, angle=30, uv="cyl"))
        objs.append(band(nm + "Rim", (yt + yb_) / 2, rr * 1.03, 0.008, "Base_" + base))
    y0, y1 = -ya - 0.048, -yb + 0.044
    rings = []
    for t, rad in ((0.0, r * 0.5), (0.1, r * 0.86), (0.5, r * 0.8), (0.88, r * 0.62), (1.0, r * 0.42)):
        y = y0 + (y1 - y0) * t
        rings.append([(rad * math.cos(2 * math.pi * i / 6 + 0.4 * t), y, rad * math.sin(2 * math.pi * i / 6 + 0.4 * t)) for i in range(6)])
    objs.append(fin(loft("LLC_Crystal", rings, "League_Crystal"), angle=20.0))
    objs.append(revolve("LLC_Vein", [(0.0, y0 - 0.005), (r * 0.16, y0 - 0.01), (r * 0.16, y1 + 0.01), (0.0, y1 + 0.005)], "League_Cyan", 8))
    return objs, limb_empties(L, r * 0.85)


def build_Limb_LeagueScythe(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Brass"):
    """Коса: парящее чёрное веретено, по внешней стороне (+X) — большое серповидное лезвие пустотного металла с фиолетовой
    кромкой, острие уходит ниже нижнего шарнира; лезвие держит латунный зажим."""
    _mats()
    objs, prof, y0, y1 = _float_limb("LLS", L, r, ja, jb, base, rmax_k=0.72)
    top, bot = y0 - 0.01, -L - r * 1.6
    outer, inner = [], []
    n = 18
    for k in range(n + 1):
        t = k / n
        y = top + (bot - top) * t
        bulge = math.sin(math.pi * min(t / 0.9, 1.0)) ** 0.8
        hook = -0.05 * max(0.0, (t - 0.8) / 0.2) ** 2   # острие загибается внутрь
        outer.append((r * 0.4 + (r * 1.9 + 0.03) * bulge + hook, y))
        inner.append((r * 0.4 + r * 0.6 * bulge * 0.9 + hook * 0.8, y))
    blade = outer + list(reversed(inner[1:-1]))
    objs.append(fin(extrude2d("LLS_Blade", blade, -0.007, 0.007, "League_Void"), 0.002, 1, angle=30.0))
    objs.append(sweep("LLS_Edge", [Vector((x, y, 0.0)) for x, y in outer], [0.005] * len(outer), "League_Glow", sides=6))
    objs.append(fin(rbox("LLS_Clamp", (r * 1.2, 0.03, r * 0.9), "Base_" + base, (r * 0.45, top - 0.02, 0.0), 0.006, 1), angle=40))
    return objs, limb_empties(L, r * 0.72)


def build_Limb_LeagueTentacle(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Щупальце лиги: живая тёмно-алая ткань S-изгибом, сужается к концу, хитиновые кольца через равные промежутки, ряд
    светящихся точек к камере и костяные крючья по внешней стороне (Base_ — кость); у сокета — тёмное кольцо-сфинктер со светом."""
    _mats()
    ya = ja * SEG_GAP
    n = 18
    pts, radii = [], []
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((0.035 * math.sin(t * math.pi * 2.0), -ya - (L - ya) * t, 0.0)))
        radii.append(r * (0.92 - 0.5 * t))
    objs = [fin(sweep("LTL_Body", pts, radii, "League_Flesh", sides=14), angle=60, uv="cyl")]
    objs += _joint_ring("LTL", 0.0, ja)
    for i in range(3, n, 4):
        d = (pts[min(i + 1, n)] - pts[i - 1]).normalized()
        objs.append(fin(revolve("LTL_Chitin", [(radii[i] * 1.02, 0.012), (radii[i] * 1.12, 0.0), (radii[i] * 1.05, -0.016),
                                               (radii[i] * 0.98, -0.014)], "League_Void", 16, align_y(d, pts[i]), closed=True),
                        angle=60))
    for i in range(2, n - 1, 3):
        objs.append(sphere("LTL_Glow", radii[i] * 0.16, tuple(pts[i] + Vector((0.0, 0.0, radii[i] * 0.94))), "League_Glow", 8, 4))
    for i in (5, 10, 14):
        side = 1.0 if math.sin(i / n * math.pi * 2.0) >= 0 else -1.0
        p = pts[i] + Vector((side * radii[i] * 0.9, 0.0, 0.0))
        hook = _bezier3(p, p + Vector((side * 0.03, 0.005, 0.0)), p + Vector((side * 0.045, -0.02, 0.0)),
                        p + Vector((side * 0.035, -0.045, 0.0)), 6)
        objs += _horn("LTL_Hook", hook, radii[i] * 0.28, "Base_" + base, sides=6)
    return objs, limb_empties(L, r * 0.8)


# ---------------------------------------------------------------------------------------------------------------------------------
# кисти и стопы (Socket в 0, кисть растёт в −Y; стопа: низ на y = −0.09, как у kit_ends)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Hand_LeagueTalon(base="Brass"):
    """Когти: кольцо сустава, чёрная манжета и ладонь, три длинных латунных когтя-серпа (Base_) с фиолетовыми остриями."""
    _mats()
    objs = _joint_ring("HLT", 0.0, 0.044)
    objs.append(fin(revolve("HLT_Cuff", [(0.0, -0.046), (0.03, -0.046), (0.042, -0.058), (0.04, -0.075), (0.0, -0.078)], "League_Void", 8),
                    0.002, 1, angle=30, uv="cyl"))
    objs.append(fin(rbox("HLT_Palm", (0.09, 0.05, 0.06), "League_Void", (0.0, -0.095, 0.0), 0.018, 2), angle=35))
    objs.append(box("HLT_PalmGlow", (0.06, 0.005, 0.006), "League_Glow", (0.0, -0.09, 0.031)))
    for sx in (-1, 0, 1):
        root = Vector((sx * 0.032, -0.115, 0.0 if sx else 0.012))
        if sx:
            ctrl = [root, root + Vector((sx * 0.06, -0.05, 0.0)), root + Vector((sx * 0.04, -0.14, 0.01)),
                    root + Vector((-sx * 0.015, -0.18, 0.02))]
        else:
            ctrl = [root, root + Vector((0.0, -0.07, 0.02)), root + Vector((0.0, -0.14, 0.05)), root + Vector((0.0, -0.165, 0.09))]
        pts = _bezier3(*ctrl, 10)
        objs += _horn("HLT_Talon", pts, 0.014, "Base_" + base, sides=8, tip="League_Glow")
        objs.append(fin(sphere("HLT_Knuckle", 0.016, tuple(root), "League_Void", 12, 6), angle=80))
    return objs, [socket(), shape_box("Hand", (0.0, -0.13, 0.0), (0.12, 0.18, 0.07))]


def build_Hand_LeaguePincer(base="Brass"):
    """Клешня лиги: кольцо сустава, чёрная манжета, две несимметричные челюсти в плоскости кадра (большая — внешняя) со
    светящейся внутренней кромкой, латунные оси (Base_)."""
    _mats()
    objs = _joint_ring("HLP", 0.0, 0.044)
    objs.append(fin(revolve("HLP_Cuff", [(0.0, -0.046), (0.034, -0.046), (0.046, -0.062), (0.044, -0.085), (0.0, -0.09)], "League_Void", 8),
                    0.002, 1, angle=30, uv="cyl"))
    for sx, big in ((1, True), (-1, False)):
        k = 1.0 if big else 0.72
        outer = [(sx * 0.02, -0.08), (sx * 0.075 * k, -0.11), (sx * 0.085 * k, -0.17 * k - 0.02), (sx * 0.05 * k, -0.23 * k),
                 (sx * 0.008, -0.25 * k)]
        inner = [(sx * 0.02 * k, -0.225 * k), (sx * 0.045 * k, -0.17 * k - 0.01), (sx * 0.035 * k, -0.12), (sx * 0.006, -0.1)]
        pts = outer + inner
        if sx < 0:
            pts = list(reversed(pts))
        objs.append(fin(extrude2d("HLP_Jaw", pts, -0.016 * k, 0.016 * k, "League_Void"), 0.003, 1, angle=35))
        edge = [Vector((x, y, 0.0)) for x, y in inner]
        objs.append(sweep("HLP_Edge", edge, 0.0045, "League_Glow", sides=5))
        for x, y in ((sx * 0.06 * k, -0.13), (sx * 0.055 * k, -0.19 * k)):
            objs.append(fin(spike("HLP_Tooth", (x - sx * 0.02, y, 0.0), (-sx, -0.3, 0.0), 0.022, 0.007, "League_Void", 5), angle=50))
        objs.append(fin(_zpivot("HLP_Pivot", (sx * 0.035, -0.095, 0.0), 0.016, 0.022 * k, "Base_" + base), 0.002, 1, angle=50))
    return objs, [socket(), shape_box("Hand", (0.0, -0.16, 0.0), (0.16, 0.17, 0.05))]


def _zpivot(name, center, r, half, mat):
    """Ось-шайба вдоль Z (к камере): цилиндр с фасками."""
    prof = [(0.0, -half), (r * 0.8, -half), (r, -half + 0.004), (r, half - 0.004), (r * 0.8, half), (0.0, half)]
    return revolve(name, prof, mat, 14, T(center) @ Rx(90.0))


def build_Foot_LeagueHover(base="Brass"):
    """Парящая стопа: подошвы нет — чёрный конус-эмиттер под кольцом сустава, латунный обод (Base_), светящееся сопло и
    полупрозрачный конус поля до земли, горизонтальное кольцо поля у самой земли (сбоку — светящаяся черта)."""
    _mats()
    objs = _joint_ring("FLH", 0.0, 0.052)
    objs.append(fin(revolve("FLH_Cone", [(0.0, -0.05), (0.062, -0.05), (0.066, -0.056), (0.036, -0.072), (0.016, -0.076), (0.0, -0.076)],
                            "League_Void", 10), 0.002, 1, angle=30, uv="cyl"))
    objs.append(band("FLH_Rim", -0.054, 0.068, 0.008, "Base_" + base))
    objs.append(sphere("FLH_Nozzle", 0.014, (0.0, -0.077, 0.0), "League_Glow", 12, 6))
    objs.append(revolve("FLH_Field", [(0.012, -0.078), (0.075, -0.0885), (0.0, -0.0885)], "League_Crystal", 24))
    objs.append(torus("FLH_Halo", (0.0, -0.0875, 0.0), 0.078, 0.0028, "League_Glow", 'XZ', 32, 5))
    return objs, [socket(), shape_cyl("Foot", (0.0, -0.07, 0.0), 0.07, 0.04)]


def build_Foot_LeagueSpike(base="Brass"):
    """Ходуля-коготь: кольцо сустава, чёрный узел-кулак и три изогнутых когтя до земли (вперёд-вбок, назад-вбок, к камере) с
    латунными наконечниками (Base_) — лапа насекомого вместо ботинка."""
    _mats()
    objs = _joint_ring("FLS", 0.0, 0.052)
    objs.append(fin(sphere("FLS_Knot", 0.034, (0.0, -0.066, 0.0), "League_Void", 12, 6), angle=40))
    for dx, dz in ((1.0, 0.35), (-1.0, 0.35), (0.0, 1.0), (0.0, -0.8)):
        d = Vector((dx, 0.0, dz)).normalized()
        root = Vector((0.0, -0.066, 0.0)) + d * 0.022
        reach = 0.1 if dz > -0.5 else 0.06
        pts = _bezier3(root, root + d * 0.04 + Vector((0.0, 0.02, 0.0)), root + d * reach * 0.9 + Vector((0.0, 0.0, 0.0)),
                       Vector((0.0, -0.088, 0.0)) + d * reach, 8)
        objs += _horn("FLS_Claw", pts, 0.014, sides=6)
        objs.append(fin(spike("FLS_Tip", tuple(pts[-3]), tuple(pts[-1] - pts[-3]), (pts[-1] - pts[-3]).length + 0.006, 0.008,
                              "Base_" + base, 6), angle=50))
    return objs, [socket(), shape_box("Foot", (0.0, -0.07, 0.02), (0.2, 0.04, 0.16))]


# ---------------------------------------------------------------------------------------------------------------------------------
# навершия оружия (как kit_weapons: Socket в проушине, рукоять снизу, деталь растёт в −Y)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Blade_LeagueCrystal(base="Brass"):
    """Кристальный клинок: обойма с полоской цвета игрока, латунная гарда-полумесяц (Base_), узкий ромбический клинок из
    энергокристалла с голубой прожилкой по оси, чёрные шипы гарды со светящимися концами."""
    _mats()
    objs = _collar("BLC", -0.07, stripe=-0.05)
    objs.append(fin(revolve("BLC_Neck", [(0.0, -0.06), (0.032, -0.06), (0.034, -0.08), (0.026, -0.1), (0.0, -0.1)], "League_Void", 16),
                    0.002, 1, uv="cyl"))
    guard = [(-0.11, -0.085), (-0.06, -0.1), (0.0, -0.105), (0.06, -0.1), (0.11, -0.085), (0.1, -0.108), (0.05, -0.122), (0.0, -0.126),
             (-0.05, -0.122), (-0.1, -0.108)]
    objs.append(fin(extrude2d("BLC_Guard", guard, -0.018, 0.018, "Base_" + base), 0.003, 1, angle=40))
    for sx in (-1, 1):
        objs.append(fin(spike("BLC_Horn", (sx * 0.1, -0.1, 0.0), (sx * 0.8, 0.6, 0.0), 0.07, 0.012, "League_Void", 6), angle=50))
        objs.append(sphere("BLC_HornTip", 0.006, (sx * (0.1 + 0.056), -0.1 + 0.042, 0.0), "League_Glow", 8, 4))

    def section(y, hw, t):
        return [(hw, y, 0.0), (0.0, y, t), (-hw, y, 0.0), (0.0, y, -t)]

    st = [(-0.11, 0.024, 0.012), (-0.2, 0.036, 0.012), (-0.4, 0.032, 0.01), (-0.56, 0.02, 0.008), (-0.63, 0.008, 0.004)]
    objs.append(fin(loft("BLC_Blade", [section(y, hw, t) for y, hw, t in st], "League_Crystal", pole1=(0.0, -0.68, 0.0)), angle=20.0))
    objs.append(revolve("BLC_Vein", [(0.0, -0.1), (0.005, -0.11), (0.005, -0.58), (0.0, -0.6)], "League_Cyan", 6))
    empties = [socket(), shape_box("Collar", (0.0, -0.04, 0.0), (0.072, 0.09, 0.072)),
               shape_box("Guard", (0.0, -0.105, 0.0), (0.22, 0.04, 0.04)), shape_box("Blade", (0.0, -0.39, 0.0), (0.07, 0.55, 0.03))]
    return objs, empties


def build_Mace_LeagueOrb(base="Brass"):
    """Шар-булава лиги: обойма, латунная шейка (Base_), чёрный шар с фиолетовым светящимся экватором и шестью кристальными шипами."""
    _mats()
    objs = _collar("MLO", -0.07, stripe=-0.05)
    objs.append(fin(revolve("MLO_Neck", [(0.0, -0.06), (0.03, -0.06), (0.03, -0.1), (0.022, -0.12), (0.0, -0.125)], "Base_" + base, 16),
                    0.002, 1, uv="cyl"))
    c = Vector((0.0, -0.2, 0.0))
    R = 0.085
    objs.append(fin(sphere("MLO_Ball", R, tuple(c), "League_Void", 24, 12), angle=60.0, uv="cyl"))
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
def build_Deco_LeagueHalo(base="Brass"):
    """Гало поля (на макушку, Anchor_Top): латунная стойка (Base_), голубой шар-сенсор и парящее над ним кольцо с тремя
    фиолетовыми узлами на тонких спицах."""
    _mats()
    objs = [fin(revolve("DLH_Post", [(0.03, 0.0), (0.03, 0.015), (0.012, 0.03), (0.01, 0.1), (0.0, 0.105)], "Base_" + base, 14), 0.002, 1,
                uv="cyl")]
    objs.append(sphere("DLH_Orb", 0.026, (0.0, 0.115, 0.0), "League_Cyan", 12, 6))
    ring_y, ring_r = 0.15, 0.11
    objs.append(fin(torus("DLH_Ring", (0.0, ring_y, 0.0), ring_r, 0.009, "League_Void", 'XZ', 32, 6), angle=80))
    objs.append(torus("DLH_RingGlow", (0.0, ring_y + 0.009, 0.0), ring_r, 0.0035, "League_Glow", 'XZ', 32, 5))
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        p = Vector((ring_r * math.cos(a), ring_y, ring_r * math.sin(a)))
        objs.append(sphere("DLH_Node", 0.017, tuple(p), "League_Glow", 8, 4))
        objs.append(fin(sweep("DLH_Spoke", [Vector((0.0, 0.1, 0.0)), p], 0.003, "League_Void", sides=4), angle=60))
    return objs, [socket(rot_z=180.0), shape_cyl("Halo", (0.0, 0.09, 0.0), 0.11, 0.18)]


def build_Deco_LeagueShield(base="Brass", r=0.058):
    """Энергощит на конечность (Anchor_Deco): манжета цвета игрока, чёрный кронштейн, шестиугольная пластина энергокристалла
    перед конечностью в латунной раме (Base_); r — радиус конечности (0.058 рука, 0.074 нога)."""
    _mats()
    R = r * 1.25
    objs = [band("DLS_Cuff", -0.045, R, 0.022, "Shirt_Kit")]
    objs.append(fin(revolve("DLS_Collar", [(R * 0.98, -0.03), (R * 1.08, -0.035), (R * 1.08, -0.07), (R * 0.98, -0.075)], "League_Void", 22,
                            closed=True), 0.002, 1, uv="cyl"))
    zc = R + 0.03
    cy = -0.12 - r
    hx = [(math.cos(math.pi / 6 + k * math.pi / 3) * r * 1.9, cy + math.sin(math.pi / 6 + k * math.pi / 3) * r * 2.2) for k in range(6)]
    objs.append(fin(extrude2d("DLS_Plate", hx, zc, zc + 0.01, "League_Crystal", bend=2.0), angle=20.0))
    frame = [Vector((x, y, zc + 0.012 - 2.0 * x * x)) for x, y in hx]
    objs.append(fin(sweep("DLS_Frame", frame, 0.007, "Base_" + base, sides=6, closed=True), angle=60))
    objs.append(fin(box("DLS_Bracket", (0.03, 0.05, zc - R + 0.01), "League_Void", (0.0, -0.075, (R + zc) / 2)), 0.003, 1))
    objs.append(sphere("DLS_Emitter", 0.012, (0.0, cy, zc + 0.016), "League_Glow", 8, 4))
    return objs, [socket(), shape_box("Shield", (0.0, cy, zc), (r * 3.6, r * 4.2, 0.03))]


META = {
    "Head_LeagueEye": {"kind": "head", "title": "Голова-око (лига)", "mass": 4.2, "energy": 10, "hit_mult": 1.15},
    "Head_LeagueCrystal": {"kind": "head", "title": "Кристальная голова (лига)", "mass": 5.0, "energy": 11, "hit_mult": 1.1},
    "Head_LeagueRing": {"kind": "head", "title": "Голова-портал (лига)", "mass": 4.4, "energy": 10},
    "Head_LeagueFlesh": {"kind": "head", "title": "Живая голова (лига)", "mass": 3.8, "energy": 9},
    "Core_LeagueOrb": {"kind": "core", "title": "Ядро-око (лига)", "mass": 14.0, "energy": 0},
    "Core_LeagueGyro": {"kind": "core", "title": "Ядро-гироскоп (лига)", "mass": 15.0, "energy": 0},
    "Core_LeagueCrystal": {"kind": "core", "title": "Кристальное ядро (лига)", "mass": 16.0, "energy": 0},
    "Core_LeagueFlesh": {"kind": "core", "title": "Живое ядро (лига)", "mass": 12.0, "energy": 0},
    "Limb_LeagueFloat": {"kind": "limb", "title": "Парящая (лига)", "mass": {"S": 1.9, "L": 3.6}, "energy": {"S": 6, "L": 8}},
    "Limb_LeagueCrystal": {"kind": "limb", "title": "Кристальная (лига)", "mass": {"S": 1.8, "L": 3.6},
                           "energy": {"S": 6, "L": 8}, "hit_mult": 1.1},
    "Limb_LeagueScythe": {"kind": "limb", "title": "Коса (лига)", "mass": {"S": 2.4, "L": 4.6},
                          "energy": {"S": 7, "L": 9}, "hit_mult": 1.2},
    "Limb_LeagueTentacle": {"kind": "limb", "title": "Щупальце (лига)", "mass": {"S": 1.6, "L": 3.2},
                            "energy": {"S": 6, "L": 8}, "hit_mult": 0.9},
    "Hand_LeagueTalon": {"kind": "hand", "title": "Когти (лига)", "mass": 1.0, "energy": 4, "hit_mult": 1.15},
    "Hand_LeaguePincer": {"kind": "hand", "title": "Клешня (лига)", "mass": 1.2, "energy": 4, "hit_mult": 1.1},
    "Foot_LeagueHover": {"kind": "foot", "title": "Парящая стопа (лига)", "mass": 0.8, "energy": 4},
    "Foot_LeagueSpike": {"kind": "foot", "title": "Ходуля-коготь (лига)", "mass": 0.7, "energy": 3, "hit_mult": 1.15},
    "Blade_LeagueCrystal": {"kind": "weapon_head", "title": "Кристальный клинок (лига)", "mass": 1.1, "energy": 0, "weapon_mult": 1.5,
                            "name_prefix": "Blade"},
    "Mace_LeagueOrb": {"kind": "weapon_head", "title": "Шар-булава (лига)", "mass": 2.6, "energy": 0, "weapon_mult": 1.4,
                       "name_prefix": "Mace"},
    "Deco_LeagueHalo": {"kind": "deco", "title": "Гало поля (лига)", "mass": 0.4, "energy": 2},
    "Deco_LeagueShield": {"kind": "armor", "title": "Энергощит (лига)", "mass": {"S": 0.9, "L": 1.4}, "energy": 4},
}
