"""Конечности кита — одна система для рук и ног: Socket в 0, Anchor_End в (0, −L), Anchor_Deco у верха."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


# ----------------------------------------------------------------------------------------------------------------------
# узлы конечностей: кольцо под любым углом, точка по длине ломаной, скруглённая ломаная
# ----------------------------------------------------------------------------------------------------------------------
def _ring_at(name, pos, direction, r, h, mat, segs=20):
    """Поясок (как kit_common.band), но в любой точке и вдоль любой оси: полоска на гнутой трубе, щупальце, верёвке."""
    prof = [(r * 0.97, h / 2), (r, h * 0.3), (r, -h * 0.3), (r * 0.97, -h / 2)]
    return fin(revolve(name, prof, mat, segs, align_y(direction, pos), closed=True), 0.001, 1, angle=70)


def _along(pts, f):
    """Точка и касательная на доле f длины ломаной pts (по длине дуги, не по индексу)."""
    pts = [Vector(p) for p in pts]
    seg = [(b - a).length for a, b in zip(pts, pts[1:])]
    goal = sum(seg) * f
    for i, s in enumerate(seg):
        if goal <= s or i == len(seg) - 1:
            t = min(goal / s, 1.0) if s > 1e-9 else 0.0
            return pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()
        goal -= s
    return pts[-1], (pts[-1] - pts[-2]).normalized()


def _fillet(corners, rad, steps=7):
    """Ломаная с плавными углами: в каждом углу — квадратичная кривая Безье с касательными вдоль рёбер (гнутая труба)."""
    P = [Vector(c) for c in corners]
    out = [P[0]]
    for a, b, c in zip(P, P[1:], P[2:]):
        d0, d1 = (b - a).normalized(), (c - b).normalized()
        ang = d0.angle(d1)
        if ang < 1e-4:
            out.append(b)
            continue
        t = min(rad * math.tan(ang / 2), (b - a).length * 0.48, (c - b).length * 0.48)
        p0, p1 = b - d0 * t, b + d1 * t
        for i in range(steps + 1):
            s = i / steps
            out.append(p0 * (1 - s) ** 2 + b * (2 * s * (1 - s)) + p1 * s * s)
    out.append(P[-1])
    return out


def build_Limb_Basic(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Wood", stripe=True):
    """Базовая: деревянный колышек-бочонок, тёмные железные обоймы на обоих концах с заклёпками, полоска цвета игрока."""
    ya, yb = ja * 0.62, L - jb * 0.62
    objs = [peg("LB_Body", -ya + 0.004, -yb - 0.004, r, r * 0.9, "Base_" + base)]
    objs += ferrule("LB_TopCap", -ya + 0.012, -ya - 0.038, r * 1.1)
    objs += ferrule("LB_BotCap", -yb + 0.036, -yb - 0.01, r * 1.0)
    if stripe:
        objs.append(band("LB_Stripe", -ya - 0.068, r * 1.07, 0.022, "Shirt_Kit"))
    return objs, limb_empties(L, r)


def build_Limb_Thick(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintRed"):
    """Толстая: крашеное бревно ×1.4, три железных бандажа на болтах."""
    R = r * 1.42
    ya, yb = ja * 0.5, L - jb * 0.5
    objs = [peg("LT_Body", -ya, -yb, R, R * 0.92, "Base_" + base, bulge=0.04)]
    for t in (0.18, 0.5, 0.82):
        y = -ya - (yb - ya) * t
        objs.append(band("LT_Band", y, R * (1.05 - 0.04 * t), 0.026, "Iron"))
        objs += ring_rivets("LT_Bolt", y, R * (1.07 - 0.04 * t), 6, "Steel", 0.007, front_only=True)
    objs.append(band("LT_Stripe", -ya - (yb - ya) * 0.34, R * 1.04, 0.018, "Shirt_Kit"))
    return objs, limb_empties(L, R * 0.85)


def build_Limb_Spring(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Iron"):
    """Пружина: два литых стакана, между ними стальная спираль и шток-демпфер."""
    ya, yb = ja * 0.6, L - jb * 0.6
    objs = []
    objs.append(fin(revolve("LS_TopCup", [(0.0, -ya + 0.01), (r * 0.8, -ya + 0.01), (r * 1.05, -ya - 0.02), (r * 1.05, -ya - 0.05),
                                         (r * 0.3, -ya - 0.055), (0.0, -ya - 0.055)], "Base_" + base, 22), 0.003, 1, uv="cyl"))
    objs.append(fin(revolve("LS_BotCup", [(0.0, -yb + 0.055), (r * 0.3, -yb + 0.055), (r * 1.0, -yb + 0.05), (r * 1.0, -yb + 0.012),
                                         (r * 0.8, -yb - 0.01), (0.0, -yb - 0.01)], "Base_" + base, 22), 0.003, 1, uv="cyl"))
    y_a, y_b = -ya - 0.05, -yb + 0.05
    turns = max(3, int((y_a - y_b) / 0.03))
    pts = []
    n = turns * 16
    for i in range(n + 1):
        t = i / n
        a = TAU * turns * t
        pts.append((math.cos(a) * r * 0.86, y_a + (y_b - y_a) * t, math.sin(a) * r * 0.86))
    objs.append(fin(sweep("LS_Coil", pts, r * 0.16, "Steel", sides=6), angle=80))
    objs.append(fin(revolve("LS_Rod", [(0.0, y_a), (r * 0.28, y_a), (r * 0.28, y_b), (0.0, y_b)], "Iron", 12), uv="cyl"))
    objs.append(band("LS_Stripe", -ya - 0.035, r * 1.08, 0.016, "Shirt_Kit"))
    return objs, limb_empties(L, r)


def build_Limb_Piston(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintYellow"):
    """Телескоп/поршень: крашеный цилиндр, стальной шток, сальник, шланг."""
    ya, yb = ja * 0.55, L - jb * 0.55
    split = -ya - (yb - ya) * 0.56
    objs = [peg("LP_Tube", -ya, split, r * 1.08, r * 1.08, "Base_" + base, bulge=0.0)]
    objs.append(band("LP_Gland", split + 0.008, r * 1.16, 0.03, "Iron"))
    objs += ring_rivets("LP_GlandBolt", split + 0.008, r * 1.18, 6, "Steel", 0.006, front_only=True)
    objs.append(fin(revolve("LP_Rod", [(0.0, split), (r * 0.5, split), (r * 0.5, -yb + 0.02), (0.0, -yb + 0.02)], "Steel", 16), uv="cyl"))
    objs += ferrule("LP_Foot", -yb + 0.035, -yb - 0.01, r * 0.85)
    objs += ferrule("LP_Head", -ya + 0.01, -ya - 0.035, r * 1.14)
    hose = [(r * 1.0, -ya - 0.05, r * 0.5), (r * 1.3, -ya - 0.09, r * 0.8), (r * 1.35, split - 0.02, r * 0.75),
            (r * 1.05, -yb + 0.06, r * 0.55), (r * 0.7, -yb + 0.04, r * 0.4)]
    objs.append(fin(sweep("LP_Hose", hose, r * 0.17, "Rubber", sides=8), angle=70))
    objs.append(band("LP_Stripe", -ya - 0.06, r * 1.13, 0.018, "Shirt_Kit"))
    return objs, limb_empties(L, r * 1.05)


def build_Limb_Bone(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Кость: тонкий ствол, мыщелки-шишки на концах."""
    ya, yb = ja * 0.5, L - jb * 0.5
    prof = [(0.0, -ya), (r * 0.85, -ya - 0.01), (r * 0.62, -ya - 0.05)]
    for i in range(7):
        t = i / 6
        prof.append((r * (0.46 + 0.1 * abs(t - 0.5) * 2), -ya - 0.05 - (yb - ya - 0.1) * t))
    prof += [(r * 0.62, -yb + 0.05), (r * 0.85, -yb + 0.01), (0.0, -yb)]
    objs = [fin(revolve("LBn_Shaft", prof, "Base_" + base, 18), uv="cyl")]
    for y, s in ((-ya - 0.018, 1.0), (-yb + 0.018, 0.9)):
        for sx in (-1, 1):
            objs.append(fin(sphere("LBn_Knob", r * 0.62 * s, (sx * r * 0.42, y, 0.0), "Base_" + base, 16, 8), angle=70))
    objs.append(band("LBn_Wrap", -ya - 0.07, r * 0.62, 0.02, "Shirt_Kit"))
    return objs, limb_empties(L, r * 0.7)


def build_Limb_Plate(L=0.30, r=0.058, ja=0.064, jb=0.054, base="WoodDark"):
    """Бронированная: тёмный сегмент, три перекрывающиеся железные пластины спереди на заклёпках."""
    ya, yb = ja * 0.6, L - jb * 0.6
    objs = [peg("LPl_Body", -ya, -yb, r * 0.9, r * 0.85, "Base_" + base)]
    n = 3
    seg = (yb - ya) / n
    for i in range(n):
        top = -ya - seg * i + 0.012
        pts = superellipse(0.0, top - seg * 0.58, r * 1.15, seg * 0.62, 24, 3.5)
        objs.append(fin(extrude2d("LPl_Plate", pts, r * 0.55, r * 0.55 + 0.012, "Iron", bend=5.0), 0.003, 1))
        for sx in (-1, 1):
            x = sx * r * 0.75
            objs.append(fin(stud("LPl_Rivet", (x, top - seg * 0.25, r * 0.57 + 0.012 - 5.0 * x * x), (0, 0, 1), "Brass", 0.006, 0.004, 6)))
    objs += ferrule("LPl_Top", -ya + 0.01, -ya - 0.03, r * 1.02, rivets=0)
    objs.append(band("LPl_Stripe", -yb + 0.02, r * 0.95, 0.018, "Shirt_Kit"))
    return objs, limb_empties(L, r)


def build_Limb_Tentacle(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Pink"):
    """Щупальце: изогнутая сужающаяся «колбаса» с присосками спереди, поясок цвета игрока у основания."""
    ya = ja * 0.4
    pts, radii = [], []
    for i in range(17):
        t = i / 16
        pts.append((0.05 * math.sin(t * math.pi * 1.2), -ya - (L - ya) * t, 0.0))
        radii.append(r * (1.1 - 0.55 * t))
    objs = [fin(sweep("LTn_Body", pts, radii, "Base_" + base, sides=16), angle=60, uv="cyl")]
    for i in range(2, 15, 2):
        t = i / 16
        p = Vector(pts[i]) + Vector((0, 0, radii[i] * 0.92))
        objs.append(fin(torus("LTn_Sucker", tuple(p), radii[i] * 0.28, radii[i] * 0.1, "Bone", 'XY', 12, 5), angle=80))
    objs.append(fin(sphere("LTn_Tip", radii[-1] * 1.05, pts[-1], "Base_" + base, 12, 6), angle=80))
    p, d = _along(pts, 0.13)
    objs.append(_ring_at("LTn_Stripe", p, d, r * 1.07, 0.022, "Shirt_Kit"))
    return objs, limb_empties(L, r)


def build_Limb_Thin(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Iron"):
    """Тонкая: стальной прут ×0.42 между железными обоймами, латунный хомут посередине, воротник цвета игрока — лёгкая."""
    ya, yb = ja * 0.6, L - jb * 0.6
    rr = r * 0.42
    objs = [peg("LTh_Rod", -ya + 0.004, -yb - 0.004, rr, rr * 0.9, "Base_" + base, bulge=0.0, rings=4, segs=14)]
    objs += ferrule("LTh_TopCap", -ya + 0.012, -ya - 0.036, r * 0.86)
    objs += ferrule("LTh_BotCap", -yb + 0.034, -yb - 0.01, r * 0.8)
    ym = -ya - (yb - ya) * 0.55
    objs.append(fin(revolve("LTh_Clamp", [(rr * 0.9, ym + 0.016), (rr * 1.45, ym + 0.013), (rr * 1.55, ym + 0.006), (rr * 1.55, ym - 0.006),
                                          (rr * 1.45, ym - 0.013), (rr * 0.9, ym - 0.016)], "Brass", 16, closed=True), 0.001, 1, uv="cyl"))
    objs += ring_rivets("LTh_ClampBolt", ym, rr * 1.55, 2, "Steel", 0.006, phase=math.pi / 2)
    y_s = -ya - 0.036 - 0.022
    objs.append(fin(revolve("LTh_Stripe", [(rr * 0.9, y_s + 0.014), (rr * 1.35, y_s + 0.011), (rr * 1.42, y_s), (rr * 1.35, y_s - 0.011),
                                           (rr * 0.9, y_s - 0.014)], "Shirt_Kit", 16, closed=True), 0.001, 1, uv="cyl"))
    return objs, limb_empties(L, r * 0.5)


def build_Limb_Curved(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Rust"):
    """Гнутая труба: ржавое колено выгибается наружу (+X) и возвращается на ось — Anchor_End остаётся в (0, −L);
    фланцы с болтами на концах, муфта на вершине изгиба."""
    ya, yb = ja * 0.55, L - jb * 0.55
    R = r * 0.62
    y0, y1 = -ya - 0.034 - r * 0.2, -yb + 0.034 + r * 0.2   # короткие прямые хвосты из фланцев, дальше изгиб
    bow = L * 0.27
    path = _fillet([(0.0, -ya + 0.006, 0.0), (0.0, y0, 0.0), (bow, (y0 + y1) / 2, 0.0), (0.0, y1, 0.0), (0.0, -yb - 0.006, 0.0)],
                   r * 1.1)
    objs = [fin(sweep("LC_Pipe", path, R, "Base_" + base, sides=16), angle=50, uv="cyl")]
    objs += ferrule("LC_TopFlange", -ya + 0.012, -ya - 0.034, r * 0.98)
    objs += ferrule("LC_BotFlange", -yb + 0.034, -yb - 0.012, r * 0.92)
    apex, d = _along(path, 0.5)
    h = 0.034
    objs.append(fin(revolve("LC_Sleeve", [(R * 1.02, h / 2), (R * 1.2, h * 0.4), (R * 1.24, 0.0), (R * 1.2, -h * 0.4), (R * 1.02, -h / 2)],
                            "Iron", 18, align_y(d, apex), closed=True), 0.002, 1, angle=60))
    for a in (-1.1, 0.0, 1.1, 2.2):
        nrm = Vector((math.sin(a), 0.0, math.cos(a)))
        objs.append(fin(stud("LC_SleeveBolt", apex + nrm * R * 1.22, nrm, "Steel", 0.0065, 0.0045, 6)))
    p, d = _along(path, 0.27)
    objs.append(_ring_at("LC_Stripe", p, d, R * 1.06, 0.02, "Shirt_Kit", 18))
    em = limb_empties(L, r * 0.7)
    em.append(shape_capsule("Bow", (apex.x * 0.72, (y0 + y1) / 2, 0.0), R * 1.05, (y0 - y1) * 0.62))
    return objs, em


def build_Limb_Spiked(L=0.30, r=0.058, ja=0.064, jb=0.054, base="WoodDark"):
    """Шипастая: тёмное бревно как у базовой, три железных пояса с короткими стальными шипами (бонус к удару частью)."""
    ya, yb = ja * 0.62, L - jb * 0.62
    objs = [peg("LSp_Body", -ya + 0.004, -yb - 0.004, r, r * 0.92, "Base_" + base, rings=8, segs=20)]
    objs += ferrule("LSp_TopCap", -ya + 0.012, -ya - 0.036, r * 1.08, rivets=0)
    objs += ferrule("LSp_BotCap", -yb + 0.034, -yb - 0.01, r * 1.0, rivets=0)
    top, bot = -ya - 0.036, -yb + 0.034
    for i, t in enumerate((0.3, 0.6, 0.88)):
        y = top + (bot - top) * t
        rb = r * (1.03 - 0.06 * t)
        objs.append(band("LSp_Band", y, rb, 0.02, "Iron"))
        for k in range(6):
            a = TAU * k / 6 + math.pi / 2 + (math.pi / 6 if i % 2 else 0.0)
            nrm = Vector((math.sin(a), 0.0, math.cos(a)))
            objs.append(fin(spike("LSp_Spike", Vector((0.0, y, 0.0)) + nrm * rb * 0.97, nrm, r * 0.62, r * 0.2, "Steel", 6), angle=60))
    objs.append(band("LSp_Stripe", top + (bot - top) * 0.12, r * 1.03, 0.018, "Shirt_Kit"))
    return objs, limb_empties(L, r * 1.1)


def build_Limb_Robotic(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintYellow"):
    """Роботизированная: два квадратных крашеных сегмента на болтах, между ними стальной шток гидравлики, боковые цилиндры."""
    ya, yb = ja * 0.55, L - jb * 0.55
    w, d = r * 1.62, r * 1.5
    w2, d2 = w * 0.88, d * 0.9
    span = yb - ya
    cap = 0.026
    t1 = -ya - cap
    b1 = t1 - span * 0.42
    t2 = b1 - span * 0.12
    b2 = -yb + cap
    objs = [rbox("LRb_Upper", (w, t1 - b1, d), "Base_" + base, (0.0, (t1 + b1) / 2, 0.0), r * 0.16, 2)]
    objs.append(rbox("LRb_Lower", (w2, t2 - b2, d2), "Base_" + base, (0.0, (t2 + b2) / 2, 0.0), r * 0.15, 2))
    objs.append(rbox("LRb_TopCap", (w * 0.8, cap + 0.008, d * 0.8), "Iron", (0.0, -ya - cap / 2 + 0.004, 0.0), 0.006, 1))
    objs.append(rbox("LRb_BotCap", (w * 0.74, cap + 0.008, d * 0.74), "Iron", (0.0, -yb + cap / 2 - 0.004, 0.0), 0.006, 1))
    objs.append(fin(revolve("LRb_Gland", [(0.0, b1 + 0.004), (r * 0.5, b1 + 0.004), (r * 0.5, b1 - 0.012), (r * 0.42, b1 - 0.016),
                                          (0.0, b1 - 0.016)], "Iron", 16), 0.002, 1, uv="cyl"))
    objs.append(fin(revolve("LRb_Rod", [(0.0, b1), (r * 0.26, b1), (r * 0.26, t2 - 0.01), (0.0, t2 - 0.01)], "Steel", 12), uv="cyl"))
    # боковые гидроцилиндры: корпус вполовину утоплен в бок верхнего сегмента, шток входит в проушину на боку нижнего
    rc = r * 0.13
    c_top, c_bot = t1 - span * 0.08, b1 - span * 0.03
    y_lug = t2 - (t2 - b2) * 0.28
    for sx in (-1, 1):
        x = sx * (w / 2 + rc * 0.35)
        objs.append(fin(revolve("LRb_Cyl", [(0.0, c_top), (rc * 0.8, c_top), (rc, c_top - 0.004), (rc, c_bot + 0.004), (rc * 0.8, c_bot),
                                            (0.0, c_bot)], "Iron", 10, T((x, 0.0, 0.0))), uv="cyl"))
        objs.append(fin(revolve("LRb_CylRod", [(0.0, c_bot), (rc * 0.5, c_bot), (rc * 0.5, y_lug), (0.0, y_lug)], "Steel", 8,
                                T((x, 0.0, 0.0))), uv="cyl"))
        lug_w = abs(x) + rc * 1.1 - w2 / 2 + 0.004
        objs.append(rbox("LRb_Lug", (lug_w, rc * 2.2, rc * 2.4), "Iron", (sx * (w2 / 2 - 0.004 + lug_w / 2), y_lug - rc * 0.6, 0.0),
                         0.003, 1))
    for (tt, bb, ww, dd) in ((t1, b1, w, d), (t2, b2, w2, d2)):
        for sx in (-1, 1):
            for yy in (tt - r * 0.2, bb + r * 0.2):
                objs.append(fin(stud("LRb_Bolt", (sx * (ww / 2 - r * 0.2), yy, dd / 2), (0, 0, 1), "Steel", 0.0065, 0.0045, 6)))
    ys = t1 - (t1 - b1) * 0.55
    objs.append(rbox("LRb_Stripe", (w + 0.006, 0.02, d + 0.006), "Shirt_Kit", (0.0, ys, 0.0), 0.004, 1))
    return objs, limb_empties(L, r * 0.85)


def _rope_loop(name, center, rho, tilt, minor, mat, segs=14):
    """Петля узла: эллипс — сечение цилиндра радиуса rho плоскостью под углом tilt (вокруг Z), то есть лежит на верёвке."""
    a = rho / math.cos(math.radians(tilt))
    pts = [T(center) @ Rz(tilt) @ Vector((a * math.cos(TAU * i / segs), 0.0, rho * math.sin(TAU * i / segs), 1.0)) for i in range(segs)]
    return fin(sweep(name, [p.to_3d() for p in pts], minor, mat, sides=6, closed=True), angle=70)


def build_Limb_Rope(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Wood"):
    """Верёвка: три свитые пряди, узлы (у ноги — два), железные наконечники, обмотка цвета игрока под верхним — мягкая."""
    ya, yb = ja * 0.55, L - jb * 0.55
    objs = ferrule("LRp_TopCap", -ya + 0.012, -ya - 0.034, r * 0.84, rivets=3)
    objs += ferrule("LRp_BotCap", -yb + 0.034, -yb - 0.012, r * 0.8, rivets=3)
    y0, y1 = -ya - 0.02, -yb + 0.02
    rs, rc = r * 0.3, r * 0.29
    knots = (0.56,) if y0 - y1 < 0.25 else (0.36, 0.72)
    turns = (y0 - y1) / (r * 2.0)
    sway = r * 0.3

    def spread(t):   # у узла пряди расходятся
        return 1.0 + sum(0.55 * math.exp(-(((t - tk) * (y0 - y1)) / (r * 0.55)) ** 2) for tk in knots)

    n = 30
    for k in range(3):
        pts = []
        for i in range(n + 1):
            t = i / n
            a = TAU * (turns * t + k / 3.0)
            s = spread(t)
            pts.append((sway * math.sin(math.pi * t) + math.cos(a) * rc * s, y0 + (y1 - y0) * t, math.sin(a) * rc * s))
        objs.append(fin(sweep("LRp_Strand", pts, rs, "Base_" + base, sides=6, phase=0.5 * k), angle=70, uv="cyl"))
    for tk in knots:
        c = (sway * math.sin(math.pi * tk), y0 + (y1 - y0) * tk, 0.0)
        rho = rc * spread(tk) + rs * 0.72
        for tilt in (34.0, -34.0):
            objs.append(_rope_loop("LRp_Knot", c, rho, tilt, rs * 0.92, "Base_" + base))
    yw = -ya - 0.034 - 0.016
    for i in range(3):
        y = yw - i * 0.0085
        ring = [T((sway * math.sin(math.pi * (y0 - y) / (y0 - y1)), y, 0.0)) @ Rx(10.0 if i % 2 else -10.0) @ p.to_4d()
                for p in circle((0.0, 0.0, 0.0), rc + rs * 0.95, 'XZ', 12)]
        objs.append(fin(sweep("LRp_Whip", [p.to_3d() for p in ring], 0.0045, "Shirt_Kit", sides=5, closed=True), angle=80))
    return objs, limb_empties(L, r * 0.72)


def build_Limb_Fantasy(L=0.30, r=0.058, ja=0.064, jb=0.054, base="PaintWhite"):
    """Сказочная: точёный белый ствол с утолщением, латунные кольца и венцы, самоцвет в оправе спереди, латунная спираль."""
    ya, yb = ja * 0.6, L - jb * 0.6
    top, bot = -ya - 0.03, -yb + 0.03
    span = top - bot
    shape = [(0.0, 0.66), (0.18, 0.72), (0.42, 0.95), (0.55, 0.9), (0.72, 0.6), (0.88, 0.64), (1.0, 0.72)]

    def rad(t):   # радиус ствола на доле t от венца до ножки (гладкие ступени между ключами shape)
        t = min(max(t, 0.0), 1.0)
        for (t0, v0), (t1, v1) in zip(shape, shape[1:]):
            if t0 <= t <= t1:
                u = (t - t0) / (t1 - t0)
                return r * (v0 + (v1 - v0) * u * u * (3 - 2 * u))
        return r * shape[-1][1]

    prof = [(0.0, top + 0.01), (r * 0.62, top + 0.01)] + [(rad(i / 14), top - span * i / 14) for i in range(15)]
    prof += [(r * 0.6, bot - 0.01), (0.0, bot - 0.01)]
    objs = [fin(revolve("LF_Shaft", prof, "Base_" + base, 20), uv="cyl")]
    # верхний венец: латунная чашка с бусинами по краю
    objs.append(fin(revolve("LF_Crown", [(0.0, -ya + 0.012), (r * 0.78, -ya + 0.012), (r * 0.9, -ya - 0.004), (r * 1.02, -ya - 0.03),
                                         (r * 0.98, -ya - 0.038), (r * 0.64, -ya - 0.036), (0.0, -ya - 0.036)], "Brass", 20),
                    0.002, 1, uv="cyl"))
    for k in range(6):
        a = TAU * k / 6 + math.pi / 6
        objs.append(fin(sphere("LF_Bead", r * 0.1, (math.sin(a) * r * 0.98, -ya - 0.034, math.cos(a) * r * 0.98), "Brass", 8, 4), angle=80))
    objs += ferrule("LF_Foot", bot + 0.004, -yb - 0.008, r * 0.76, mat="Brass", rivets=0)
    # кольца над и под утолщением, оправа камня спереди (+Z)
    tg = 0.46
    yg = top - span * tg
    for dt in (-0.2, 0.22):
        rr = rad(tg + dt)
        objs.append(fin(torus("LF_Ring", (0.0, top - span * (tg + dt), 0.0), rr + r * 0.03, r * 0.08, "Brass", 'XZ', 22, 6), angle=80))
    rg = rad(tg)
    objs.append(fin(torus("LF_Bezel", (0.0, yg, rg - r * 0.04), r * 0.34, r * 0.075, "Brass", 'XY', 16, 5), angle=80))
    gem = revolve("LF_Gem", [(0.0, -r * 0.14), (r * 0.3, -r * 0.04), (r * 0.34, 0.03 * r), (r * 0.22, r * 0.14), (0.0, r * 0.17)], "Gem", 8,
                  T((0.0, yg, rg - r * 0.06)) @ Rx(90.0))
    objs.append(fin(gem, angle=20))
    # латунная спираль-филигрань по нижней части ствола — прижата к профилю
    pts = []
    t_a, t_b = tg + 0.3, 0.97
    for i in range(29):
        t = t_a + (t_b - t_a) * i / 28
        a = TAU * 1.25 * i / 28 + 0.4
        rr = rad(t) + r * 0.02
        pts.append((math.sin(a) * rr, top - span * t, math.cos(a) * rr))
    objs.append(fin(sweep("LF_Filigree", pts, r * 0.05, "Brass", sides=5), angle=80))
    objs.append(band("LF_Stripe", top - span * 0.08, rad(0.08) * 1.04, 0.018, "Shirt_Kit"))
    return objs, limb_empties(L, r * 0.85)


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3): масса и энергия по размеру (S рука 0.30 · L нога 0.42 · LA/LL — риг v3);
# Basic_S = 2.0 кг как wood_upper_arm; name_prefix по размеру — в body_kit.SIZE_PREFIX. body_mult нет: удар конечностью —
# Tuning.BODY_MULT по имени тела (плечо / предплечье / бедро / голень) × материал узла × hit_mult — множитель удара ЭТОЙ формой
# (PartDef.hit_mult, ModularDoll meta body_mult): шипы бьют сильнее (1.2 — потолок формы, WORKSHOP_V3.md §4), верёвка и щупальце — мягче (0.85 / 0.9); у остальных 1.0
META = {
    "Limb_Basic": {"kind": "limb", "title": "Базовая", "mass": {"S": 2.0, "LA": 1.5, "L": 4.0, "LL": 3.0},
                   "energy": {"S": 4, "LA": 4, "L": 6, "LL": 6}},
    "Limb_Thick": {"kind": "limb", "title": "Толстая", "mass": {"S": 3.6, "L": 7.0}, "energy": {"S": 7, "L": 9}},
    "Limb_Spring": {"kind": "limb", "title": "Пружина", "mass": {"S": 2.4, "L": 4.4}, "energy": {"S": 5, "L": 7}},
    "Limb_Piston": {"kind": "limb", "title": "Поршень", "mass": {"S": 2.8, "L": 5.2}, "energy": {"S": 6, "L": 8}},
    "Limb_Bone": {"kind": "limb", "title": "Кость", "mass": {"S": 1.3, "L": 2.6}, "energy": {"S": 3, "L": 5}},
    "Limb_Plate": {"kind": "limb", "title": "Бронированная", "mass": {"S": 3.2, "L": 6.0}, "energy": {"S": 6, "L": 8}},
    "Limb_Tentacle": {"kind": "limb", "title": "Щупальце", "mass": {"S": 1.6, "L": 3.0}, "energy": {"S": 5, "L": 7}, "hit_mult": 0.9},
    "Limb_Thin": {"kind": "limb", "title": "Тонкая", "mass": {"S": 1.1, "L": 2.2}, "energy": {"S": 3, "L": 4}},
    "Limb_Curved": {"kind": "limb", "title": "Гнутая труба", "mass": {"S": 2.2, "L": 4.4}, "energy": {"S": 5, "L": 7}},
    "Limb_Spiked": {"kind": "limb", "title": "Шипастая", "mass": {"S": 2.7, "L": 5.4}, "energy": {"S": 6, "L": 8}, "hit_mult": 1.2},
    "Limb_Robotic": {"kind": "limb", "title": "Робо-гидравлика", "mass": {"S": 3.0, "L": 5.8}, "energy": {"S": 7, "L": 9}},
    "Limb_Rope": {"kind": "limb", "title": "Верёвка", "mass": {"S": 1.2, "L": 2.4}, "energy": {"S": 3, "L": 5}, "hit_mult": 0.85},
    "Limb_Fantasy": {"kind": "limb", "title": "Сказочная", "mass": {"S": 2.2, "L": 4.4}, "energy": {"S": 5, "L": 7}},
}
