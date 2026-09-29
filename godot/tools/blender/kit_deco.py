"""Броня и декор кита (attach fixed — сливаются с телом родителя): на Anchor_Top головы, Anchor_Deco конечности, Anchor_Back ядра.
Формы Shape_* декора переезжают в тело-хозяина и правда бьются (BODY_KIT.md §6): маленькие, по габариту детали, через z = 0,
толщина по z ≥ 0.06."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита

# Anchor_Back ядра — за спиной, на z = −0.14 от плоскости куклы (HUMAN_ANCHORS, у хаба так же). Все тела живут у z = 0,
# поэтому формы декора на спине тянутся по z от детали (−0.03) до плоскости куклы (+0.03): иначе с соседями не встретятся
_BACK_Z = 0.14


def _capsule(name, a, b, r):
    """Капсула-форма в плоскости XY: центры полусфер в a и b (x, y)."""
    a, b = Vector((a[0], a[1], 0.0)), Vector((b[0], b[1], 0.0))
    d = b - a
    return shape_capsule(name, tuple((a + b) / 2), r, d.length + 2 * r, math.degrees(math.atan2(-d.x, d.y)))


def _back_box(name, cx, cy, sx, sy, rot_z=0.0):
    """Бокс-форма декора на Anchor_Back: x/y — честный габарит, по z — от −0.03 до плоскости куклы (+_BACK_Z + 0.03)."""
    return shape_box(name, (cx, cy, _BACK_Z / 2), (sx, sy, _BACK_Z + 0.06), rot_z)


def _surf_n(x, bend):
    """Нормаль лицевой стороны листа z = −bend·x² (extrude2d с bend) в точке x."""
    return Vector((2.0 * bend * x, 0.0, 1.0)).normalized()


def build_Deco_Horns(base="Bone"):
    """Рога на макушку (Anchor_Top головы): железный обруч + два изогнутых рога."""
    objs = [fin(torus("DH_Band", (0.0, -0.02, 0.0), 0.11, 0.014, "Iron", 'XZ', 28, 6), angle=80)]
    shapes = []
    for sx in (-1, 1):
        pts, radii = [], []
        for i in range(14):
            t = i / 13
            pts.append((sx * (0.1 + 0.13 * math.sin(t * 1.2)), -0.03 + 0.18 * t ** 1.2 - 0.03 * math.sin(t * math.pi), 0.0))
            radii.append(0.034 * (1 - t) ** 0.85 + 0.003)
        objs.append(fin(sweep("DH_Horn", pts, radii, "Base_" + base, sides=10), angle=60))
        # по капсуле на рог: хорда от корня над обручем (t = 2/13) до кончика (t = 12/13), r ~ средняя толщина рога
        shapes.append(_capsule("Horn_L" if sx > 0 else "Horn_R", pts[2], pts[12], 0.03))
    return objs, [socket(rot_z=180.0)] + shapes


def build_Deco_Crown(base="Brass"):
    """Корона (лор: Корона Башни): обруч с пятью зубцами, шарики на концах, камни."""
    prof = [(0.085, -0.03), (0.092, -0.028), (0.092, 0.02), (0.085, 0.022)]
    objs = [fin(revolve("DC_Band", prof, "Base_" + base, 28, closed=False), 0.002, 1, uv="cyl")]
    for k in range(5):
        a = TAU * k / 5 + math.pi / 2
        p = Vector((math.cos(a) * 0.088, 0.015, math.sin(a) * 0.088))
        objs.append(fin(spike("DC_Tine", p, (math.cos(a) * 0.15, 1.0, math.sin(a) * 0.15), 0.07, 0.02, "Base_" + base, 8), angle=70))
        objs.append(fin(sphere("DC_Pearl", 0.011, tuple(p + Vector((math.cos(a) * 0.01, 0.072, math.sin(a) * 0.01))), "Base_" + base, 10, 5)))
        g = Vector((math.cos(a + TAU / 10) * 0.094, -0.005, math.sin(a + TAU / 10) * 0.094))
        objs.append(fin(sphere("DC_Gem", 0.012, tuple(g), "Gem", 10, 5), angle=80))
    # цилиндр: обруч (−0.03) … шарики на зубцах (≈ 0.098)
    return objs, [socket(rot_z=180.0), shape_cyl("Crown", (0.0, 0.033, 0.0), 0.096, 0.13)]


def build_Deco_Pauldron(base="RustRed"):
    """Наплечник на Anchor_Deco конечности: выпуклая пластина снаружи-сверху + вторая ламель + заклёпки. Купол сидит ниже по
    конечности (Y0) и смотрит больше наружу, чем вверх (D): шар сустава плеча (и шестерня мотора, если шарнир — мотор) виден."""
    D = Vector((0.82, 0.57, 0.0)).normalized()   # ось купола в осях детали: наружу (+X) и немного к суставу (+Y)
    Y0 = -0.065                                  # центр верхней ламели от Socket (было −0.01: купол накрывал шар плеча)
    R0 = 0.088
    objs = []
    for i, (r, off) in enumerate(((R0, 0.0), (0.078, -0.05))):
        prof = [(0.0, r), (r * 0.5, r * 0.87), (r * 0.8, r * 0.6), (r * 0.97, r * 0.2), (r, 0.0)]
        shell = revolve("DP_Lame%d" % i, prof, "Base_" + base, 24, align_y(tuple(D), (0.0, Y0 + off, 0.0)))
        objs.append(fin(shell, 0.003, 1, angle=45.0))
        objs.append(fin(torus("DP_Rim%d" % i, (0.0, 0.0, 0.0), r, 0.006, "Iron", 'XZ', 24, 5), angle=80))
        objs[-1].matrix_world = G2B @ align_y(tuple(D), (0.0, Y0 + off, 0.0)) @ B2G @ objs[-1].matrix_world
    for k in range(3):
        a = math.radians(-40 + 40 * k)
        d = align_y(tuple(D)).to_3x3() @ Vector((math.sin(a) * 0.55, 0.83, math.cos(a) * 0.55))
        objs.append(fin(stud("DP_Rivet", tuple(d * R0 + Vector((0, Y0, 0))), tuple(d), "Brass", 0.008, 0.005, 6)))
    objs.append(fin(spike("DP_Spike", tuple(Vector((0.0, Y0, 0.0)) + D * R0 * 0.94), tuple(D), 0.07, 0.017, "Steel", 8), angle=60))
    # бокс в осях купола (Y → D): поперёк обе ламели, вдоль D — от края нижней ламели до основания шипа
    p = Vector((-D.y, D.x, 0.0))
    c = Vector((0.0, Y0, 0.0)) - p * 0.01 + D * 0.031
    shape = shape_box("Pauldron", tuple(c), (0.19, 0.13, 0.165), math.degrees(math.atan2(-D.x, D.y)))
    return objs, [socket(), shape]


def build_Deco_Spikes(base="Iron", r=0.058):
    """Шипастый ошейник на конечность (Anchor_Deco): обруч и шесть шипов вокруг — физический бонус к удару частью."""
    y = -0.05
    objs = [band("DS_Ring", y, r * 1.18, 0.034, "Base_" + base)]
    for k in range(6):
        a = TAU * k / 6 + 0.3
        d = Vector((math.sin(a), 0.0, math.cos(a)))
        objs.append(fin(spike("DS_Spike", tuple(Vector((0, y, 0)) + d * r * 1.15), tuple(d), 0.06, 0.016, "Steel", 8), angle=60))
    # цилиндр вокруг конечности: обруч + две трети шипа (острия торчат — ими и цепляется)
    return objs, [socket(), shape_cyl("Spikes", (0.0, y, 0.0), r * 1.15 + 0.04, 0.05)]


def build_Deco_Banner(base="WoodDark"):
    """Флажок на спине (Anchor_Back ядра): древко, навершие, полотнище цвета игрока с латунной короной."""
    objs = [fin(revolve("DB_Pole", [(0.0, -0.03), (0.012, -0.03), (0.012, 0.52), (0.0, 0.52)], "Base_" + base, 10), uv="cyl")]
    objs.append(fin(sphere("DB_Finial", 0.022, (0.0, 0.535, 0.0), "Brass", 14, 7), angle=80))
    flag = [(0.0, 0.5), (-0.24, 0.5), (-0.2, 0.395), (-0.24, 0.29), (0.0, 0.29)]
    objs.append(fin(extrude2d("DB_Flag", flag, -0.004, 0.004, "Shirt_Kit", bend=0.4), 0.002, 1))
    crown = [(-0.07, 0.35), (-0.15, 0.35), (-0.155, 0.43), (-0.135, 0.395), (-0.11, 0.44), (-0.085, 0.395), (-0.065, 0.43)]
    objs.append(fin(extrude2d("DB_Crown", crown, 0.004, 0.009, "Brass", bend=0.4), 0.001, 1))
    # древко с навершием и полотнище — тонкие боксы (по z — до плоскости куклы, см. _BACK_Z)
    return objs, [socket(rot_z=180.0), _back_box("Pole", 0.0, 0.25, 0.03, 0.58), _back_box("Flag", -0.12, 0.395, 0.24, 0.21)]


def build_Deco_Wings(base="RustRed"):
    """Жестяные крылья-перепонки на спину (Anchor_Back ядра): крашеный лист, выгнутый назад, на железных «пальцах» с латунными
    заклёпками, коготь на сгибе, петли на пластине-упряжи, кругляш цвета игрока на каждом крыле."""
    bend = 0.4                                      # лист выгнут назад: z = −bend·x², кончики уходят за спину
    objs = [rbox("DW_Harness", (0.17, 0.1, 0.03), "Iron", (0.0, 0.035, -0.012), 0.008, 2)]
    shapes = []
    # Anchor_Back — на уровне плеч: крыло поднято над плечом и головой по бокам, иначе его закрывают руки и ядро
    R0, W, R1 = Vector((0.07, 0.10)), Vector((0.26, 0.41)), Vector((0.09, -0.03))   # корень сверху, «запястье», корень снизу
    tips = [Vector((0.52, 0.33)), Vector((0.50, 0.13)), Vector((0.37, -0.02))]
    contour = [R0, Vector((0.15, 0.27)), W, tips[0]]
    for P, Q in zip(tips, tips[1:] + [R1]):         # задняя кромка — фестоны между пальцами (выгнуты к запястью)
        nrm = Vector((-(Q - P).y, (Q - P).x)).normalized()
        if nrm.dot(W - (P + Q) / 2) < 0.0:
            nrm = -nrm
        for s in (0.25, 0.5, 0.75):
            contour.append(P + (Q - P) * s + nrm * (Q - P).length * 0.2 * math.sin(math.pi * s))
        contour.append(Q)
    for sx in (-1, 1):
        def at(v, lift=0.0):
            x = sx * v.x
            return Vector((x, v.y, -bend * x * x)) + _surf_n(x, bend) * (0.003 + lift)
        objs.append(fin(extrude2d("DW_Sheet", [(sx * v.x, v.y) for v in contour], -0.003, 0.003, "Base_" + base, bend=bend),
                        0.0015, 1, angle=50.0))
        for a, b, rr in [(R0, W, 0.011)] + [(W, t, 0.008) for t in tips]:
            line = [at(a + (b - a) * (k / 4), rr * 0.4) for k in range(5)]
            objs.append(fin(sweep("DW_Spar", line, [rr, rr, rr, rr * 0.85, rr * 0.6], "Iron", sides=6), angle=60))
            if rr < 0.01:
                for s in (0.45, 0.8):
                    v = a + (b - a) * s
                    objs.append(fin(stud("DW_Rivet", at(v, rr * 1.2), _surf_n(sx * v.x, bend), "Brass", 0.0065, 0.004, 6)))
        objs.append(fin(sphere("DW_Knuckle", 0.017, tuple(at(W, 0.006)), "Iron", 12, 6), angle=80))
        objs.append(fin(spike("DW_Claw", tuple(at(W, 0.006)), (sx * 0.35, 1.0, 0.0), 0.06, 0.011, "Steel", 8), angle=60))
        hl = (R0 - R1).length
        objs.append(fin(revolve("DW_Hinge", [(0.0, -0.005), (0.015, -0.005), (0.017, 0.004), (0.017, hl - 0.004), (0.015, hl + 0.005),
                                             (0.0, hl + 0.005)], "Iron", 14,
                                align_y((sx * (R0.x - R1.x), R0.y - R1.y, 0.0), (sx * R1.x, R1.y, -0.004))), 0.0, uv="cyl"))
        c = Vector((0.356, 0.215))                  # кругляш между средними пальцами
        objs.append(fin(revolve("DW_Roundel", [(0.0, 0.0), (0.034, 0.0), (0.034, 0.004), (0.0, 0.004)], "Shirt_Kit", 20,
                                align_y(_surf_n(sx * c.x, bend), at(c, -0.001))), 0.0))
        # бокс на основную часть перепонки (фестоны и кончики пальцев — снаружи)
        shapes.append(_back_box("Wing_L" if sx > 0 else "Wing_R", sx * 0.29, 0.18, 0.32, 0.3))
    return objs, [socket(rot_z=180.0)] + shapes


def _feather(prefix, root, phi, length, width, droop, mat, splits=()):
    """Перо: плоское опахало (лофт колец — широкое в плоскости XY, тонкое по z) со скруглённым концом и костяной стержень спереди.
    phi — отклонение от вертикали (рад, + к +X), droop — насколько перо свисает к концу, кончик загнут назад (−z);
    splits — надрывы кромки [(кольцо, сторона ±1, доля ширины)]: мультяшное перо, а не лист."""
    N, n, th = 48, 14, 0.004
    fine, p = [Vector(root)], Vector(root)
    for k in range(1, N + 1):                       # осевая линия: курс отклоняется наружу к концу (свисает)
        t = k / N
        h = phi + math.copysign(droop, phi) * t * t if abs(phi) > 1e-6 else 0.0
        p = p + Vector((math.sin(h), math.cos(h), 0.0)) * (length / N)
        fine.append(Vector((p.x, p.y, -0.08 * t * t)))

    def frame(i):
        tan = (fine[min(i + 1, N)] - fine[max(i - 1, 0)]).normalized()
        wd = tan.cross(Vector((0.0, 0.0, 1.0))).normalized()
        td = wd.cross(tan).normalized()
        return wd, (td if td.z >= 0.0 else -td)

    cut = {(k, sd): f for k, sd, f in splits}
    rings = []
    for k in range(1, n):
        t = 1.0 - (1.0 - k / n) ** 1.4             # кольца гуще к концу — конец скруглён, а не остёр
        i = round(t * N)
        wd, td = frame(i)
        w = width * (t ** 0.5) * ((1.0 - t) ** 0.25) / 0.62      # узкое у стержня, широкое к концу
        ring = []
        for q in range(8):
            c = math.cos(TAU * q / 8)
            ring.append(fine[i] + wd * w * c * cut.get((k, 1 if c > 0 else -1), 1.0) + td * th * math.sin(TAU * q / 8))
        rings.append(ring)
    vane = fin(loft(prefix + "_Vane", rings, mat, pole0=fine[0], pole1=fine[-1]), angle=70)
    quill = [fine[i] + frame(i)[1] * th * 0.8 for i in range(0, 41, 4)]
    rad = [0.0045 - 0.0025 * k / (len(quill) - 1) for k in range(len(quill))]
    return [vane, fin(sweep(prefix + "_Quill", quill, rad, "Bone", sides=5), angle=70)]


def build_Deco_Plume(base="Brass"):
    """Султан на макушку (Anchor_Top головы): латунная втулка на фланце с болтами, железный бандаж, веер из пяти перьев цвета
    игрока с костяными стержнями; крайние перья свисают наружу, кончики загнуты назад."""
    prof = [(0.0, -0.012), (0.042, -0.012), (0.045, -0.004), (0.04, 0.0), (0.022, 0.006), (0.02, 0.05), (0.026, 0.062),
            (0.03, 0.074), (0.018, 0.077), (0.0, 0.068)]
    objs = [fin(revolve("DPl_Holder", prof, "Base_" + base, 20), 0.0, angle=50.0, uv="cyl")]
    objs.append(band("DPl_Band", 0.03, 0.023, 0.014, "Iron"))
    for k in range(4):
        a = TAU * k / 4 + math.pi / 4
        objs.append(fin(stud("DPl_Bolt", (math.sin(a) * 0.033, 0.002, math.cos(a) * 0.033), (math.sin(a) * 0.3, 1.0, math.cos(a) * 0.3),
                             "Steel", 0.0065, 0.0045, 6)))
    for j, (phi, length, width, droop) in enumerate(((-1.0, 0.22, 0.03, 0.8), (-0.5, 0.28, 0.033, 0.5), (0.0, 0.33, 0.036, 0.0),
                                                     (0.5, 0.28, 0.033, 0.5), (1.0, 0.22, 0.03, 0.8))):
        sd = 1 if j % 2 else -1
        objs += _feather("DPl_Feather", (math.sin(phi) * 0.006, 0.058, 0.0), phi, length, width, droop, "Shirt_Kit",
                         splits=((8 + j % 2, sd, 0.5), (11, -sd, 0.72)))
    # бокс на плотную часть веера (свисающие концы крайних перьев — снаружи: они мягкие)
    return objs, [socket(rot_z=180.0), shape_box("Plume", (0.0, 0.19, 0.0), (0.26, 0.3, 0.06))]


def build_Deco_Antenna(base="Iron"):
    """Антенна на макушку (Anchor_Top головы): литой колпак на трёх болтах, стальная пружина на штыре, гибкий хлыст с манжетой
    и шар цвета игрока на конце."""
    objs = [fin(revolve("DA_Mount", [(0.0, -0.012), (0.04, -0.012), (0.042, -0.003), (0.034, 0.012), (0.02, 0.028), (0.012, 0.034),
                                     (0.0, 0.034)], "Base_" + base, 20), 0.002, 1, angle=40.0, uv="cyl")]
    for k in range(3):
        a = TAU * k / 3 + math.pi / 3
        d = Vector((math.sin(a), 0.9, math.cos(a))).normalized()
        objs.append(fin(stud("DA_Bolt", (math.sin(a) * 0.036, 0.004, math.cos(a) * 0.036), tuple(d), "Steel", 0.0065, 0.0045, 6)))
    y0, y1, turns = 0.03, 0.125, 5
    coil = []
    for i in range(turns * 12 + 1):
        t = i / (turns * 12)
        a = TAU * turns * t
        coil.append((math.cos(a) * 0.014, y0 + (y1 - y0) * t, math.sin(a) * 0.014))
    objs.append(fin(sweep("DA_Coil", coil, 0.0038, "Steel", sides=5), angle=80))
    objs.append(fin(revolve("DA_Pin", [(0.0, y0 - 0.005), (0.006, y0 - 0.005), (0.006, y1 + 0.01), (0.0, y1 + 0.01)], "Iron", 10),
                    uv="cyl"))
    objs.append(fin(revolve("DA_Collar", [(0.0, y1 - 0.004), (0.017, y1 - 0.004), (0.018, y1 + 0.006), (0.012, y1 + 0.014),
                                          (0.0, y1 + 0.014)], "Iron", 14), 0.0, uv="cyl"))
    whip = [(0.028 * (k / 8) ** 2, y1 + 0.012 + 0.2 * k / 8, 0.0) for k in range(9)]
    objs.append(fin(sweep("DA_Whip", whip, [0.0048 - 0.0015 * k / 8 for k in range(9)], "Steel", sides=6), angle=70))
    tip = Vector(whip[-1])
    dirn = (tip - Vector(whip[-2])).normalized()
    objs.append(fin(revolve("DA_TipCup", [(0.0, -0.008), (0.006, -0.008), (0.011, 0.006), (0.0, 0.006)], "Iron", 10,
                            align_y(dirn, tip)), uv="cyl"))
    ball = tip + dirn * 0.03
    objs.append(fin(sphere("DA_Ball", 0.028, tuple(ball), "Shirt_Kit", 16, 8), angle=80))
    return objs, [socket(rot_z=180.0), _capsule("Antenna", (0.0, 0.02), (ball.x, ball.y), 0.03)]


def build_Deco_Chimney(base="Rust"):
    """Труба-дымоход на спину (Anchor_Back ядра): колено из ядра вбок к левому плечу (мимо головы), клёпаная труба,
    жаровое кольцо (свечение за решёткой), раструб с тлеющим жерлом, полоска цвета игрока."""
    X, rp = 0.24, 0.03                              # ось трубы над плечом: голова (±0.175 с уголками) её не закрывает
    path = [Vector((0.0, -0.02, 0.0)), Vector((0.0, 0.03, 0.0))]
    for k in range(1, 6):                           # колено 1: вверх → вбок (+X), радиус 0.06
        a = math.pi - math.pi / 2 * k / 5
        path.append(Vector((0.06 + 0.06 * math.cos(a), 0.03 + 0.06 * math.sin(a), 0.0)))
    for k in range(1, 6):                           # колено 2: вбок → вверх
        a = -math.pi / 2 + math.pi / 2 * k / 5
        path.append(Vector((X - 0.06 + 0.06 * math.cos(a), 0.15 + 0.06 * math.sin(a), 0.0)))
    objs = [fin(sweep("DCh_Elbow", path, rp, "Base_" + base, sides=14), 0.0, angle=60.0, uv="cyl")]
    prof = [(0.0, 0.14), (0.032, 0.14), (0.032, 0.37), (0.036, 0.385), (0.05, 0.42), (0.058, 0.435), (0.056, 0.445),
            (0.046, 0.442), (0.038, 0.43), (0.0, 0.43)]
    objs.append(fin(revolve("DCh_Stack", prof, "Base_" + base, 20, T((X, 0.0, 0.0))), 0.0015, 1, angle=45.0, uv="cyl"))
    objs.append(fin(revolve("DCh_Ember", [(0.0, 0.431), (0.037, 0.431), (0.037, 0.433), (0.0, 0.433)], "CoreGlow", 16,
                            T((X, 0.0, 0.0))), 0.0))
    for y in (0.2, 0.365):
        objs.append(fin(revolve("DCh_Band", [(0.033, y + 0.011), (0.037, y + 0.008), (0.037, y - 0.008), (0.033, y - 0.011)], "Iron",
                                20, T((X, 0.0, 0.0)), closed=True), 0.001, 1, uv="cyl"))
        for r in ring_rivets("DCh_Rivet", y, 0.037, 8, "Brass", 0.0055, front_only=True, phase=math.pi / 8):
            r.matrix_world = G2B @ T((X, 0.0, 0.0)) @ B2G @ r.matrix_world
            objs.append(r)
    objs.append(fin(revolve("DCh_Stripe", [(0.031, 0.242), (0.034, 0.238), (0.034, 0.222), (0.031, 0.218)], "Shirt_Kit", 20,
                            T((X, 0.0, 0.0)), closed=True), 0.0, uv="cyl"))
    # жаровое кольцо: светящийся поясок за шестью железными прутьями решётки
    objs.append(fin(revolve("DCh_Glow", [(0.03, 0.331), (0.036, 0.327), (0.036, 0.293), (0.03, 0.289)], "CoreGlow", 20,
                            T((X, 0.0, 0.0)), closed=True), 0.0))
    for k in range(6):
        a = math.pi * (k + 0.5) / 6                 # решётка — только на лицевой половине (z > 0)
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        base_p = Vector((X, 0.0, 0.0)) + d * 0.039
        objs.append(fin(sweep("DCh_Bar", [base_p + Vector((0.0, 0.291, 0.0)), base_p + Vector((0.0, 0.329, 0.0))], 0.0035, "Iron",
                              sides=4), angle=60))
    return objs, [socket(rot_z=180.0), _back_box("Stack", X, 0.29, 0.1, 0.3), _back_box("Pipe", 0.12, 0.09, 0.24, 0.065)]


def build_Deco_Gauntlet(base="Iron", r=0.058):
    """Наруч на конечность (Anchor_Deco): три железные ламели внахлёст (верхняя накрывает нижнюю, книзу уже — по конечности),
    выгнутый щиток спереди с ребром, латунные заклёпки, манжета цвета игрока сверху; r — радиус конечности (0.058 рука, 0.074 нога)."""
    R, t, flare = r * 1.26, 0.007, 1.12
    hl, lap = r * 0.9, 0.01
    y0 = -0.05
    y_bot = y0 - 3 * hl + 2 * lap
    yc, hh, hw = (y0 + y_bot) / 2, (y0 - y_bot) * 0.46, R * 0.55
    objs = [band("DG_Cuff", y0 + 0.007, R * 1.02, 0.02, "Shirt_Kit")]
    y = y0
    for i in range(3):
        Ri = R * (1.0 - 0.055 * i)
        prof = [(Ri - 0.003, y), (Ri + t, y), (Ri * flare + t, y - hl), (Ri * flare - 0.003, y - hl)]
        objs.append(fin(revolve("DG_Lame", prof, "Base_" + base, 24, closed=True), 0.0025, 1, angle=40.0, uv="cyl"))
        rr = Ri * (1.0 + (flare - 1.0) * 0.45) + t
        for k in range(8):                          # заклёпки по лицевой половине, кроме спрятанных под щитком
            a = TAU * k / 8 + math.pi / 8 * (i % 2)
            nrm = Vector((math.sin(a), 0.0, math.cos(a)))
            if nrm.z < -0.2 or (nrm.z > 0.0 and abs(nrm.x) * rr < hw + 0.008):
                continue
            objs.append(fin(stud("DG_Rivet", Vector((0.0, y - hl * 0.45, 0.0)) + nrm * rr, nrm, "Brass", 0.0065, 0.0042, 6)))
        y -= hl - lap
    # щиток: лист по цилиндру вокруг самой широкой ламели, ребро по центру, четыре заклёпки по углам
    zc = R * flare + t - 0.001
    bend = 1.0 / (2.0 * (zc + 0.004))
    objs.append(fin(extrude2d("DG_Plate", superellipse(0.0, yc, hw, hh, 24, 3.0), zc, zc + 0.008, "Base_" + base, bend=bend),
                    0.003, 1, angle=50.0))
    objs.append(fin(sweep("DG_Ridge", [(0.0, yc + hh * 0.8, zc + 0.01), (0.0, yc, zc + 0.011), (0.0, yc - hh * 0.8, zc + 0.01)],
                          0.0055, "Iron", sides=6), angle=60))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = sx * hw * 0.62
            objs.append(fin(stud("DG_PlateRivet", (x, yc + sy * hh * 0.72, zc + 0.008 - bend * x * x), (2.0 * bend * x, 0.0, 1.0),
                                 "Brass", 0.007, 0.0045, 6)))
    return objs, [socket(), shape_cyl("Gauntlet", (0.0, yc, 0.0), R * flare + t, y0 - y_bot)]


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3, §6): декор и броня — fixed; body_mult > 1 — бонус к удару телом-хозяином.
# Детали с r (размер S / L, body_kit.sized): масса по размеру — наруч — лист по окружности и высоте, ~(r_L / r_S)² = ×1.6;
# у ошейника высота ленты и шипы постоянные, растёт только окружность — ~×1.3
META = {
    "Deco_Horns": {"kind": "deco", "title": "Рога", "mass": 0.8, "energy": 2, "body_mult": 1.2},
    "Deco_Crown": {"kind": "deco", "title": "Корона", "mass": 0.4, "energy": 1},
    "Deco_Pauldron": {"kind": "armor", "title": "Наплечник", "mass": 1.5, "energy": 3},
    "Deco_Spikes": {"kind": "deco", "title": "Шипастый ошейник", "mass": {"S": 0.6, "L": 0.8}, "energy": 3, "body_mult": 1.25},
    "Deco_Banner": {"kind": "deco", "title": "Флажок", "mass": 0.5, "energy": 1},
    "Deco_Wings": {"kind": "deco", "title": "Жестяные крылья", "mass": 1.2, "energy": 3},
    "Deco_Plume": {"kind": "deco", "title": "Султан", "mass": 0.3, "energy": 1},
    "Deco_Antenna": {"kind": "deco", "title": "Антенна", "mass": 0.3, "energy": 1},
    "Deco_Chimney": {"kind": "deco", "title": "Дымоход", "mass": 1.0, "energy": 2},
    "Deco_Gauntlet": {"kind": "armor", "title": "Наруч", "mass": {"S": 1.2, "L": 2.0}, "energy": 3, "body_mult": 1.1},
}
