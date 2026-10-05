"""Живые детали Аоэлюн (листы автора 04.10.2026 «Аоэлюн — живые модули»; лор — docs/plan-demo/LORE_V2.md, раздел 2б; описание —
docs/plan-demo/AI_ASSET_BRIEF.md). Контракт — как у остального кита (docs/plan-demo/BODY_KIT.md).

Аоэлюн — живой самонастраивающийся модульный организм («модульная кукла без пилота»): детали выращены, а не собраны. Язык формы —
продолжение живых деталей лиги (kit_league.py: Head_LeagueFlesh, Core_LeagueFlesh, Limb_LeagueTentacle), роли материалов те же:
    Base_<Mat>    кость цвета слоновой кости — пластины-скорлупы, лезвия, когти, шипы (ось материалов: перекрашивается в мастерской);
    League_Flesh  тёмно-алая мышца — жилы, узлы суставов, подкладка панциря;
    League_Void   чёрный хитин — манжеты, кольца сегментов, веки, маски;
    League_Glow   фиолетовый свет — режущие кромки лезвий, глаза, швы, кольца суставов;
    Shirt_Kit     цвет игрока — только у ядра (парящее кольцо, как у ядер лиги).
Сустав — как у лиги: у сокета кольцо поля вокруг шара (_joint_ring), сегмент начинается на SEG_GAP радиуса шара. Жутко, но чисто:
без крови и ран. Удар формой — META hit_mult (лезвия / когти ×1.2, ходуля и голова-охотник ×1.15, плеть / крюк / наблюдатель ×1.1).
"""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита
import common as C  # noqa: F401
import craft_parts as K  # noqa: F401
from kit_deco import _back_box
from kit_league import BALL_ANCHORS, SEG_GAP, _bezier3, _bosses, _float_band, _horn, _joint_ring, _mats, _prof_r

_Y, _Z = Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0))


# ---------------------------------------------------------------------------------------------------------------------------------
# общие узлы живого языка: лезвие, пластина-скорлупа, мышечный пучок, глаз
# ---------------------------------------------------------------------------------------------------------------------------------
def _blade(name, pts, width, thick, mat, nrm=(0.0, 0.0, 1.0), side=1.0, glow="League_Glow", ke=0.6, back=0.35, taper=0.7, wprof=None,
           toward=None):
    """Костяное лезвие / коготь по кривой pts (от корня к острию): плоское сечение в плоскости с нормалью nrm, режущая кромка — в
    сторону side · (касательная × nrm); width — ширина (к острию сходит на нет: taper — показатель, меньше — полнее лезвие),
    thick — толщина у обуха. glow — материал светящейся кромки (клин по режущей стороне, доля 1 − ke ширины); None — кость до
    самой кромки. wprof(t) — свой профиль ширины (0..1) вместо когтя. toward — постоянное направление к кромке вместо nrm / side:
    лезвие гнётся «языком» поперёк своей плоскости (лепесток, загнутый вперёд)."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    nv = Vector(nrm).normalized()
    body, edge = [], []
    for i in range(n - 1):
        t = i / (n - 1)
        p = pts[i]
        tg = (pts[i + 1] - pts[max(i - 1, 0)]).normalized()
        if toward is not None:
            e = (Vector(toward) - tg * Vector(toward).dot(tg)).normalized()
        else:
            e = tg.cross(nv).normalized() * side      # к режущей кромке
        b = e.cross(tg).normalized()                  # поперёк пластины (толщина)
        f = wprof(t) if wprof else (0.6 + 0.4 * min(t / 0.2, 1.0)) * (1.0 - t) ** taper
        w = width * f
        th = thick * 0.5 * (0.45 + 0.55 * f)
        sb, se = -w * back, w * (1.0 - back)          # обух и кромка от осевой
        sk = sb + (se - sb) * (ke if glow else 1.0)   # граница кости и светящегося клина
        sm = sb + (se - sb) * 0.3
        te = th * (0.55 if glow else 0.12)
        body.append([tuple(p + e * sb + b * th * 0.55), tuple(p + e * sm + b * th), tuple(p + e * sk + b * te),
                     tuple(p + e * sk - b * te), tuple(p + e * sm - b * th), tuple(p + e * sb - b * th * 0.55)])
        if glow:
            edge.append([tuple(p + e * se), tuple(p + e * (sk - w * 0.03) + b * te), tuple(p + e * (sk - w * 0.03) - b * te)])
    out = [fin(loft(name, body, mat, pole1=tuple(pts[-1])), angle=35.0)]
    if glow:
        out.append(loft(name + "Edge", edge, glow, pole1=tuple(pts[-1])))
    return out


def _shell(name, fn, mat, thick=0.009, nu=6, nv=4, ref=None, tip0=False, tip1=True, angle=62.0):
    """Пластина-скорлупа: наружная сторона — поверхность fn(u, v) → точка (u ∈ 0..1 вдоль, v ∈ −1..1 поперёк), внутренняя утоплена
    на thick по нормали (наружу — от ref(p), точки «внутри»; по умолчанию — ось Y). tip0 / tip1 — конец сходится в остриё
    (ширина fn там нулевая), иначе торец закрыт."""
    ref = ref or (lambda p: Vector((0.0, p.y, 0.0)))

    def normal(u, v):
        e = 0.004
        du = fn(min(u + e, 1.0), v) - fn(max(u - e, 0.0), v)
        dv = fn(u, min(v + e, 1.0)) - fn(u, max(v - e, -1.0))
        p = fn(u, v)
        nr = du.cross(dv)
        if nr.length < 1e-10:
            nr = p - ref(p)
        nr.normalize()
        return nr if nr.dot(p - ref(p)) >= 0.0 else -nr

    rings = []
    for i in range(1 if tip0 else 0, nu if tip1 else nu + 1):
        u = i / nu
        vs = [-1.0 + 2.0 * j / nv for j in range(nv + 1)]
        outer = [fn(u, v) for v in vs]
        inner = [fn(u, v) - normal(u, v) * thick for v in reversed(vs)]
        rings.append([tuple(p) for p in outer + inner])
    pole0 = tuple(fn(0.0, 0.0) - normal(0.5 / nu, 0.0) * thick * 0.5) if tip0 else None
    pole1 = tuple(fn(1.0, 0.0) - normal(1.0 - 0.5 / nu, 0.0) * thick * 0.5) if tip1 else None
    return fin(loft(name, rings, mat, pole0=pole0, pole1=pole1), angle=angle)


def _scale_w(u, p=2.2):
    """Ширина чешуи по длине: широкая у верха, к нижнему острию сходится (лист / чешуя панциря)."""
    return math.sqrt(max(1.0 - u ** p, 0.0))


def _leaf(t):
    """Профиль ширины лепестка: узкий корень, полная середина, длинное остриё."""
    return 1.15 * math.sin(math.pi * (0.16 + 0.84 * t)) ** 0.8 * (1.0 - t) ** 0.35


def _sinew(name, pts, radii, strands=4, twist=0.8, k=0.58, mat="League_Flesh", sides=6, phase=0.0, core="League_Void"):
    """Мышечный пучок вдоль осевой pts (кривая в плоскости XY): strands жил идут винтом (twist оборотов на длину), радиус пучка —
    radii по точкам; в середине — тёмная сердцевина, она закрывает просветы между жилами."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    objs = []
    for s in range(strands):
        sp, sr = [], []
        for i, p in enumerate(pts):
            tg = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            a = tg.cross(_Z).normalized()
            ph = phase + TAU * s / strands + TAU * twist * i / (n - 1)
            sp.append(p + (a * math.cos(ph) + _Z * math.sin(ph)) * radii[i] * k)
            sr.append(radii[i] * (1.0 - k) * 1.08)
        objs.append(fin(sweep(name, sp, sr, mat, sides=sides), angle=60, uv="cyl"))
    if core:
        objs.append(fin(sweep(name + "Core", pts, [rr * k * 1.02 for rr in radii], core, sides=8), angle=60, uv="cyl"))
    return objs


def _lumps(o, center, amp=0.05, f=60.0):
    """Бугры живой ткани: рябь вдоль радиуса от center (координаты Godot) — живая ткань не бывает ровной. Рябь чётная по X:
    деталь остаётся симметричной."""
    c = G2B @ Vector(center)
    for v in o.data.vertices:
        d = v.co - c
        v.co = c + d * (1.0 + amp * math.cos(d.x * f) * math.sin(d.y * f * 0.8 + d.z * f * 0.6))
    return o


def _knot(name, r, center, amp=0.05, segs=12, rings=6, mat="League_Flesh"):
    """Мышечный узел сустава: бугристый шар живой ткани."""
    return fin(_lumps(sphere(name, r, center, mat, segs, rings), center, amp, 2.6 / r), angle=60.0, uv="cyl")


def _eye(prefix, c, d, r, pupil=True, lid="League_Void", segs=12):
    """Глаз Аоэлюн: хитиновое веко-кольцо, светящаяся фиолетовая радужка-купол, тёмный зрачок (ось взгляда — d)."""
    xf = align_y(d, c)
    objs = [fin(revolve(prefix + "_Lid", [(r * 1.02, -r * 0.5), (r * 1.36, -r * 0.2), (r * 1.22, r * 0.28), (r * 0.96, r * 0.16)], lid,
                        segs, xf, closed=True), angle=50.0, uv="cyl")]
    objs.append(revolve(prefix + "_Iris", [(r, 0.0), (r * 0.66, r * 0.48), (0.0, r * 0.62)], "League_Glow", segs, xf))
    if pupil:
        objs.append(revolve(prefix + "_Pupil", [(r * 0.36, r * 0.44), (r * 0.22, r * 0.64), (0.0, r * 0.7)], "League_Void", 10, xf))
    return objs


def _pores(name, pts, r=0.007):
    """Поры в костяной пластине: в них видна алая ткань под костью (точки — на поверхности пластины)."""
    return [sphere(name, r, tuple(p), "League_Flesh", 8, 4) for p in pts]


def _cuffs(prefix, y0, y1, r, kt=0.74, kb=0.66):
    """Хитиновые манжеты-сфинктеры на торцах живого сегмента (y0 — верхний торец, y1 — нижний): из них выходит мышца."""
    out = []
    for nm, y, k, dn in ((prefix + "_CuffT", y0, kt, -1.0), (prefix + "_CuffB", y1, kb, 1.0)):
        prof = [(0.0, y), (r * k * 0.72, y), (r * k, y + dn * 0.008), (r * k * 0.97, y + dn * 0.022), (r * k * 0.7, y + dn * 0.03),
                (0.0, y + dn * 0.03)]
        out.append(fin(revolve(nm, prof, "League_Void", 14), angle=40.0, uv="cyl"))
    return out


def _limb_plate(y_top, y_bot, rad, a0, half, lift=0.008, keel=0.005, bulge=0.0):
    """Поверхность костяной пластины на конечности для _shell: от y_top до y_bot вокруг оси Y, середина — на угле a0 (0° — к камере,
    90° — +X), полуширина half° у верха, к низу — остриё; rad(y) — радиус под пластиной, lift — отгиб острия, keel — гладкий киль
    по середине, bulge — выпуклость пластины посередине длины."""
    def fn(u, v):
        y = y_top + (y_bot - y_top) * u
        a = math.radians(a0 + half * _scale_w(u) * v)
        rr = rad(y) + lift * u * u + keel * (1.0 - v * v) ** 2 + bulge * math.sin(math.pi * u) * (1.0 - 0.6 * v * v)
        return Vector((rr * math.sin(a), y, rr * math.cos(a)))
    return fn


# ---------------------------------------------------------------------------------------------------------------------------------
# ядро
# ---------------------------------------------------------------------------------------------------------------------------------
def _on_ball(deg, pol, sx=1):
    """Направление из центра шара-ядра: deg — угол в плоскости кадра XY (как у BALL_ANCHORS), pol — отклонение от оси взгляда +Z;
    sx = −1 — зеркало (правая сторона)."""
    a, p = math.radians(deg), math.radians(pol)
    return Vector((sx * math.cos(a) * math.sin(p), math.sin(a) * math.sin(p), math.cos(p)))


def build_Core_AoeHeart(base="Bone"):
    """Ядро-сердце: чёрный хитиновый шар с огромным фиолетовым глазом (мышечное кольцо, костяное веко, кольца радужки, зрачок с
    искрой). Вокруг глаза — венец из шести костяных лепестков-«языков» со светящейся кромкой на алых мышечных узлах (острия
    загнуты вперёд, к взгляду) и пара костяных серпов-жвал под глазом; между лепестками — алые шипы, над большим глазом — три
    малых, снизу — ребристое живое подбрюшье. Цвет игрока — парящее кольцо под глазом; гнёзда суставов — как у шаров лиги."""
    _mats()
    R = 0.2
    objs = [fin(sphere("CAH_Ball", R, (0, 0, 0), "League_Void", 22, 11), angle=60.0, uv="cyl")]
    belly = [(0.0, -R - 0.008)] + [(math.sqrt(R * R - y * y) + 0.006 + 0.004 * math.sin(y * 200.0), y)
                                   for y in (-0.196, -0.186, -0.176, -0.166, -0.158)] + [(math.sqrt(R * R - 0.152 ** 2) - 0.004, -0.152)]
    objs.append(fin(revolve("CAH_Belly", belly, "League_Flesh", 20), angle=60.0, uv="cyl"))
    # большой глаз: взгляд чуть вверх; мышечное кольцо → костяное веко → радужка → тёмное кольцо → зрачок → искра
    eye = align_y((0.0, 0.1, 1.0), (0.0, 0.0, 0.0))
    objs.append(fin(revolve("CAH_Socket", [(0.122, 0.15), (0.13, 0.168), (0.116, 0.182), (0.1, 0.178)], "League_Flesh", 24, eye,
                            closed=True), angle=60.0, uv="cyl"))
    objs.append(fin(revolve("CAH_Lid", [(0.102, 0.17), (0.109, 0.185), (0.098, 0.199), (0.084, 0.201), (0.078, 0.188)], "Base_" + base,
                            24, eye, closed=True), angle=50.0, uv="cyl"))
    objs.append(revolve("CAH_Iris", [(0.08, 0.187), (0.052, 0.204), (0.0, 0.211)], "League_Glow", 24, eye))
    objs.append(revolve("CAH_IrisRing", [(0.047, 0.203), (0.052, 0.2085), (0.057, 0.2015)], "League_Void", 20, eye, closed=True))
    objs.append(revolve("CAH_Pupil", [(0.03, 0.205), (0.02, 0.213), (0.0, 0.216)], "League_Void", 12, eye))
    objs.append(revolve("CAH_Spark", [(0.011, 0.213), (0.007, 0.219), (0.0, 0.221)], "League_Glow", 8, eye))
    # венец лепестков: корни — на передней полусфере (z > 0.09: перед плоскостью конечностей), между гнёздами суставов
    for deg, ln, curl in ((64.0, 0.115, 0.4), (20.0, 0.135, 0.7), (-25.0, 0.125, 0.8), (-74.0, 0.0, 0.0)):
        ph = math.radians(deg)
        rh, tg = Vector((math.cos(ph), math.sin(ph), 0.0)), Vector((-math.sin(ph), math.cos(ph), 0.0))
        root = _on_ball(deg, 62.0) * (R - 0.004)
        if ln > 0.0:   # лепесток — «язык» шириной вдоль окружности: лицом к взгляду, остриё загнуто вперёд
            ctrl = [root, root + rh * ln * 0.5 + _Z * 0.012, root + rh * ln + _Z * 0.05 + tg * curl * ln * 0.2,
                    root + rh * ln * 0.84 + _Z * 0.125 + tg * curl * ln * 0.4]
        else:          # нижняя пара — серпы-жвалы в плоскости кадра, острия сведены под глазом, кромки — друг к другу
            ctrl = [root, root + rh * 0.05 + _Z * 0.02, root + rh * 0.09 - tg * 0.028 + _Z * 0.032,
                    root + rh * 0.066 - tg * 0.066 + _Z * 0.036]
        for sx in (1, -1):
            pts = [Vector((sx * p.x, p.y, p.z)) for p in _bezier3(*ctrl, 7)]
            if ln > 0.0:
                objs += _blade("CAH_Petal", pts, 0.074, 0.017, "Base_" + base, toward=(sx * tg.x, tg.y, tg.z), wprof=_leaf, back=0.5,
                               ke=0.68)
            else:
                objs += _blade("CAH_Petal", pts, 0.05, 0.017, "Base_" + base, side=sx, taper=0.6)
            objs.append(_knot("CAH_PetalKnot", 0.03, (sx * root.x, root.y, root.z), 0.06, 8, 4))
    for deg in (43.0, -2.5, -52.0):   # алые шипы между лепестками
        for sx in (1, -1):
            d = _on_ball(deg, 70.0, sx)
            objs.append(fin(spike("CAH_Thorn", tuple(d * (R - 0.004)), tuple(d + _Z * 0.25), 0.055, 0.016, "League_Flesh", 6), angle=50.0))
    for deg, pol, rr in ((90.0, 49.0, 0.017), (47.0, 46.0, 0.013), (133.0, 46.0, 0.013)):
        d = _on_ball(deg, pol)
        objs += _eye("CAH_Eye", tuple(d * (R + rr * 0.1)), tuple(d), rr, pupil=False, segs=10)
    objs += _float_band("CAH", -0.13, math.sqrt(R * R - 0.13 ** 2) + 0.03)
    bo, empties = _bosses("CAH", R, BALL_ANCHORS, mat="League_Void", ring="League_Flesh")
    objs += bo
    empties.append(anchor("Back", (0.0, 0.14, -0.14), 180.0))
    empties.append(shape_sphere("Torso", (0, 0, 0), R))
    return objs, empties


# ---------------------------------------------------------------------------------------------------------------------------------
# головы: FacePlate — в перепонке между жвалами (как у Head_LeagueFlesh); растут вверх, Socket повёрнут на 180°
# ---------------------------------------------------------------------------------------------------------------------------------
def _flesh_neck(prefix):
    """Шейка живой головы: мышечный стебель и кольцо сустава вокруг шара шеи (Neck 0.05)."""
    return [fin(revolve(prefix + "_Neck", [(0.0, 0.03), (0.03, 0.03), (0.04, 0.05), (0.062, 0.07), (0.0, 0.075)], "League_Flesh", 16),
                0.0, angle=60.0, uv="cyl")] + _joint_ring(prefix, 0.0, 0.05)


def build_Head_AoeWatcher(base="Bone"):
    """Голова-наблюдатель: высокая голова, вытянутая назад (темя уходит за плоскость лица). Сверху — костяной череп-маска с тремя
    глазницами: в большой — фиолетовый глаз с искрой, в двух малых у скул — глаза-сенсоры; по темени — костяной гребень. Под
    черепом — хитин, ниже — алая ткань с перепонкой под фото между двумя алыми жвалами; из-под скул свисают два длинных костяных
    клыка со светящейся кромкой."""
    _mats()
    prof = [(0.0, 0.06), (0.056, 0.064), (0.098, 0.1), (0.12, 0.15), (0.128, 0.21), (0.122, 0.27), (0.1, 0.325), (0.06, 0.365),
            (0.0, 0.378)]
    k_lean = 1.4

    def dz(y):   # наклон головы назад: чем выше, тем дальше
        return -k_lean * max(y - 0.2, 0.0) ** 2

    def lean(o):
        """Тело вращения → вытянутая назад голова: затылок длиннее лба, темя сдвинуто назад."""
        for v in o.data.vertices:
            g = B2G @ v.co
            z = g.z * (1.0 + 0.3 * min(max((g.y - 0.15) / 0.1, 0.0), 1.0)) if g.z < 0.0 else g.z
            v.co = G2B @ Vector((g.x, g.y, z + dz(g.y)))
        return o

    bulb = revolve("HAW_Bulb", prof, "League_Flesh", 20)
    for v in bulb.data.vertices:   # бугры, как у живой головы лиги (чётные по X — голова симметрична)
        co = v.co
        k = 1.0 + 0.03 * math.cos(co.x * 60.0) * math.sin(co.z * 45.0 + co.y * 30.0)
        v.co = (co.x * k, co.y * k, co.z)
    objs = [fin(lean(bulb), 0.0, angle=60.0, uv="cyl")]
    hood = [(_prof_r(prof, 0.18) - 0.004, 0.18)] + [(_prof_r(prof, y) + 0.008, y) for y in (0.187, 0.25, 0.31, 0.36)] + [(0.0, 0.388)]
    objs.append(fin(lean(revolve("HAW_Hood", hood, "League_Void", 20)), angle=50.0, uv="cyl"))
    # череп-маска: тонкая скорлупа поверх хитина, глазницы прорезаны насквозь
    outer = [(0.147, 0.198), (0.147, 0.24), (0.136, 0.29), (0.112, 0.335), (0.075, 0.372), (0.036, 0.394), (0.0, 0.402)]
    inner = [(0.0, 0.391), (0.03, 0.385), (0.066, 0.364), (0.102, 0.33), (0.125, 0.288), (0.136, 0.24), (0.136, 0.198)]
    skull = lean(revolve("HAW_Skull", outer + inner, "Base_" + base, 20, closed=True, phase=math.pi / 20))
    for v in skull.data.vertices:   # кромка — аркой: над лицом выше, у скул и на затылке опущена
        g = B2G @ v.co
        if g.y < 0.26:
            v.co = G2B @ Vector((g.x, g.y - 0.6 * (0.26 - g.y) * (1.0 - max(g.z, 0.0) / 0.15) ** 2, g.z))
    cut_sphere(skull, (0.0, 0.25, 0.161 + dz(0.25)), 0.06, 16)
    for sx in (1, -1):
        cut_sphere(skull, (sx * 0.0907, 0.236, 0.1257 + dz(0.236)), 0.021, 10)
    objs.append(fin(skull, angle=50.0, uv="cyl"))
    ridge = [(0.0, y, _prof_r(outer, y) + dz(y) + 0.002) for y in (0.315, 0.35, 0.38)] + [(0.0, 0.405, dz(0.402))] + [
        (0.0, y, -_prof_r(outer, y) * 1.3 + dz(y) - 0.002) for y in (0.385, 0.35, 0.3)]
    objs.append(fin(sweep("HAW_Ridge", ridge, [0.006, 0.011, 0.014, 0.015, 0.014, 0.012, 0.006], "Base_" + base, sides=6), angle=60.0))
    objs += _pores("HAW_Pore", [(sx * x, y, math.sqrt(_prof_r(outer, y) ** 2 - x * x) + dz(y) - 0.002)
                                for x, y in ((0.066, 0.312), (0.108, 0.262)) for sx in (1, -1)], 0.0085)
    eye = (0.0, 0.25, 0.132 + dz(0.25))
    objs += _eye("HAW_Eye", eye, (0.0, 0.08, 1.0), 0.038, segs=16)
    objs.append(revolve("HAW_EyeSpark", [(0.006, 0.026), (0.0, 0.03)], "League_Glow", 8, align_y((0.0, 0.08, 1.0), eye)))
    for sx in (1, -1):
        nr = Vector((sx * 0.585, 0.0, 0.811))
        objs += _eye("HAW_EyeS", tuple(nr * 0.1345 + Vector((0.0, 0.236, dz(0.236)))), tuple(nr), 0.0115, pupil=False, segs=10)
        fang = _bezier3((sx * 0.13, 0.225, 0.02), (sx * 0.17, 0.15, 0.06), (sx * 0.152, 0.06, 0.11), (sx * 0.1, -0.03, 0.13), 8)
        objs += _blade("HAW_Fang", fang, 0.062, 0.017, "Base_" + base, side=-sx, taper=0.55)
        jaw = _bezier3((sx * 0.07, 0.125, 0.09), (sx * 0.105, 0.07, 0.14), (sx * 0.075, 0.0, 0.165), (sx * 0.02, -0.03, 0.15), 8)
        objs += _horn("HAW_Mandible", jaw, 0.02, "League_Flesh", sides=6, tip="League_Glow")
    objs += _flesh_neck("HAW")
    face = face_plate("FacePlate", (0.0, 0.135, 0.13), 0.11, 0.07, bend=1.2, cols=8, rows=5, round_n=3.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.39, 0.0), 180.0), shape_sphere("Head", (0.0, 0.215, 0.0), 0.155)]
    return objs, empties, [face]


def build_Head_AoeHunter(base="Bone"):
    """Голова-охотник: низкий широкий клин — алая ткань под хитиновым капюшоном, шесть малых фиолетовых глаз клином, костяной
    клюв-щиток на лбу; от висков назад и вверх веером уходят по три длинных костяных лезвия со светящейся кромкой; под скулами —
    два коротких костяных резца, между ними перепонка под фото."""
    _mats()
    prof = [(0.0, 0.06), (0.05, 0.064), (0.098, 0.09), (0.124, 0.13), (0.13, 0.175), (0.112, 0.225), (0.065, 0.258), (0.0, 0.268)]
    sx_, sz_ = 1.22, 0.92   # клин: шире по X, площе по Z

    def surf(x, y, lift=0.0):
        """z поверхности клина (+ lift) над точкой (x, y)."""
        rr = _prof_r(prof, y) + lift
        return sz_ * math.sqrt(max(rr * rr - (x / sx_) ** 2, 0.0))

    wedge = revolve("HAH_Wedge", prof, "League_Flesh", 22, S((sx_, 1.0, sz_)))
    for v in wedge.data.vertices:
        co = v.co
        k = 1.0 + 0.025 * math.cos(co.x * 60.0) * math.sin(co.z * 45.0 + co.y * 30.0)
        v.co = (co.x * k, co.y * k, co.z)
    objs = [fin(wedge, 0.0, angle=60.0, uv="cyl")]
    hood = [(_prof_r(prof, 0.166) - 0.004, 0.166)] + [(_prof_r(prof, y) + 0.008, y) for y in (0.172, 0.2, 0.225, 0.258)] + [(0.0, 0.277)]
    objs.append(fin(revolve("HAH_Hood", hood, "League_Void", 22, S((sx_, 1.0, sz_))), angle=50.0, uv="cyl"))

    def beak(u, v):   # костяной щиток: от макушки вниз, остриём между глазами
        y = 0.264 - 0.07 * u
        ang = math.radians(48.0) * (1.0 - u ** 1.3) * v
        rr = _prof_r(prof, y) + 0.014
        return Vector((sx_ * rr * math.sin(ang), y, sz_ * rr * math.cos(ang)))

    objs.append(_shell("HAH_Beak", beak, "Base_" + base, 0.01, nu=6, nv=4, ref=lambda p: Vector((0.0, 0.16, 0.0))))
    objs += _pores("HAH_Pore", [beak(0.3, 0.5), beak(0.3, -0.5)])
    for x, y, r in ((0.046, 0.196, 0.015), (0.086, 0.206, 0.012), (0.119, 0.198, 0.0095)):
        for sx in (1, -1):
            z = surf(x, y, 0.008)
            nrm = Vector((sx * x / sx_ ** 2, 0.0, z / sz_ ** 2)).normalized()
            objs += _eye("HAH_Eye", (sx * x, y, z + r * 0.1), tuple(nrm), r, pupil=False, segs=10)
    for sx in (1, -1):
        # веер лезвий: верхнее — самое длинное и крутое, нижнее — почти вбок; все уходят назад (−Z)
        for k, (rx, ry, rz, dx, dy, dz) in enumerate(((0.062, 0.243, 0.03, 0.115, 0.215, -0.15), (0.103, 0.226, 0.01, 0.175, 0.14, -0.13),
                                                      (0.134, 0.2, -0.005, 0.18, 0.045, -0.11))):
            root = Vector((sx * rx, ry, rz))
            tip = Vector((sx * dx, dy, dz))
            out = Vector((sx * dy, -dx, 0.0)).normalized()   # наружу-вниз от хорды: туда выгнуто лезвие и смотрит кромка
            pts = _bezier3(root, root + tip * 0.3 + out * 0.05, root + tip * 0.7 + out * 0.045, root + tip, 8)
            objs += _blade("HAH_Blade%d" % k, pts, 0.082 - 0.008 * k, 0.017, "Base_" + base, side=sx, taper=0.5)
        tusk = _bezier3((sx * 0.092, 0.118, 0.07), (sx * 0.112, 0.07, 0.11), (sx * 0.09, 0.025, 0.135), (sx * 0.04, -0.012, 0.14), 7)
        objs += _blade("HAH_Tusk", tusk, 0.034, 0.014, "Base_" + base, side=-sx, glow=None)
    objs += _flesh_neck("HAH")
    face = face_plate("FacePlate", (0.0, 0.128, 0.125), 0.118, 0.07, bend=2.2, cols=8, rows=5, round_n=3.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.285, 0.0), 180.0), shape_box("Head", (0.0, 0.165, 0.0), (0.3, 0.21, 0.21))]
    return objs, empties, [face]


# ---------------------------------------------------------------------------------------------------------------------------------
# конечности (L, r, ja, jb — как у kit_limbs; размеры S / L даёт body_kit.sized). Сегмент — от −ja·SEG_GAP до −L + jb·SEG_GAP
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Limb_AoeSinew(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Жила — базовый живой сегмент: скрученный пучок из четырёх алых мышечных жил между двумя хитиновыми манжетами, три узкие
    костяные пластины-скорлупы уступами (внешняя — внутренняя — внешняя, острия вниз), между ними видна мышца; хитиновые кольца
    и светящиеся точки на открытой мышце; у сокета — кольцо сустава."""
    _mats()
    y0, y1 = -ja * SEG_GAP, -L + jb * SEG_GAP
    ya, h = y0 - 0.014, y0 - y1 - 0.028

    def rad(y):   # радиус пучка: брюшко посередине, сухожилия к торцам
        return r * (0.5 + 0.36 * math.sin(math.pi * min(max((ya - y) / h, 0.0), 1.0)) ** 0.7)

    objs = _joint_ring("LAS", 0.0, ja) + _cuffs("LAS", y0, y1, r)
    n = 12
    pts = [Vector((0.0, ya - h * i / n, 0.0)) for i in range(n + 1)]
    objs += _sinew("LAS_Sinew", pts, [rad(p.y) for p in pts], strands=4, twist=1.1)
    over = lambda y: rad(y) * 1.07 + 0.004   # noqa: E731 — пластины лежат поверх мышцы
    for k, (ta, tb, a0, half) in enumerate(((0.02, 0.5, 44.0, 42.0), (0.27, 0.76, -36.0, 40.0), (0.56, 0.99, 32.0, 36.0))):
        fn = _limb_plate(ya - h * ta, ya - h * tb, over, a0, half, 0.007, 0.004, r * 0.07)
        objs.append(_shell("LAS_Plate", fn, "Base_" + base, 0.01, nu=6, nv=6))
        objs += _pores("LAS_Pore", [fn(0.3, 0.4 if k % 2 else -0.4)], r * 0.12)
    for t in (0.3, 0.78):   # хитиновые кольца: видны там, где мышца открыта, остальное — под пластинами
        y = ya - h * t
        objs.append(fin(revolve("LAS_Ring", [(rad(y) * 1.0, y + 0.012), (rad(y) * 1.1, y + 0.004), (rad(y) * 1.1, y - 0.006),
                                             (rad(y) * 1.0, y - 0.012)], "League_Void", 14, closed=True), angle=60.0, uv="cyl"))
    for t, deg in ((0.1, -40.0), (0.2, -62.0), (0.62, 62.0), (0.9, -38.0)):
        y = ya - h * t
        a = math.radians(deg)
        objs.append(sphere("LAS_Glow", r * 0.11, (rad(y) * 1.02 * math.sin(a), y, rad(y) * 1.02 * math.cos(a)), "League_Glow", 8, 4))
    return objs, limb_empties(L, r)


def build_Limb_AoeBlade(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Лезвия: тонкий мышечный пучок в хитиновых манжетах, костяной щиток у плеча, а по внешней стороне (+X) — три костяных
    лезвия-серпа внахлёст, как перья крыла, со светящейся фиолетовой кромкой наружу; нижнее острие уходит за нижний шарнир."""
    _mats()
    y0, y1 = -ja * SEG_GAP, -L + jb * SEG_GAP
    ya, h = y0 - 0.014, y0 - y1 - 0.028

    def rad(y):
        return r * (0.44 + 0.24 * math.sin(math.pi * min(max((ya - y) / h, 0.0), 1.0)) ** 0.7)

    objs = _joint_ring("LAB", 0.0, ja) + _cuffs("LAB", y0, y1, r, 0.68, 0.6)
    n = 10
    pts = [Vector((0.0, ya - h * i / n, 0.0)) for i in range(n + 1)]
    objs += _sinew("LAB_Sinew", pts, [rad(p.y) for p in pts], strands=3, twist=0.9)
    over = lambda y: rad(y) * 1.07 + 0.004   # noqa: E731
    objs.append(_shell("LAB_Plate", _limb_plate(ya - h * 0.02, ya - h * 0.46, over, -18.0, 46.0, 0.007, 0.004, r * 0.06), "Base_" + base,
                       0.01, nu=6, nv=6))
    # гребень-ложе лезвий по внешней стороне: хитиновый валик, из него растут корни
    objs.append(fin(sweep("LAB_Ridge", [(rad(ya - h * t) * 0.8, ya - h * t, 0.0) for t in (0.06, 0.3, 0.55, 0.8)],
                          [r * 0.3, r * 0.34, r * 0.3, r * 0.22], "League_Void", sides=8), angle=60.0, uv="cyl"))
    for k, (ty, ln, z) in enumerate(((0.12, 0.68, 0.016), (0.38, 0.57, 0.0), (0.63, 0.45, -0.016))):
        root = Vector((r * 0.42, ya - h * ty, z))
        ln *= L
        ctrl = [root, root + Vector((r * 1.6, 0.014, 0.0)), root + Vector((r * 2.0 + ln * 0.14, -ln * 0.5, 0.0)),
                root + Vector((r * 0.9 + ln * 0.12, -ln, 0.0))]
        objs += _blade("LAB_Blade%d" % k, _bezier3(*ctrl, 10), r * (1.3 - 0.12 * k), 0.017, "Base_" + base, side=-1.0, taper=0.5)
        objs.append(_knot("LAB_Knot", r * 0.36, tuple(root + Vector((r * 0.14, 0.0, 0.0))), 0.06, 8, 4))
    return objs, limb_empties(L, r * 0.8)


def build_Limb_AoeWhip(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Плеть: S-образный хвост из позвонков-чаш (каждый следующий вложен в предыдущий и тоньше): алая ткань, хитиновая губа по
    верху, костяной щиток к камере и пара костяных шипов вбок (на выпуклой стороне изгиба — длинный); между позвонками светятся
    точки. Начало и конец — на оси (Anchor_End в (0, −L, 0))."""
    _mats()
    ya = ja * SEG_GAP
    n = max(4, round(L / 0.06))
    amp = L * 0.11

    def cl(t):
        return Vector((amp * math.sin(t * TAU), -ya - (L - ya - jb * 0.4) * t, 0.0))

    objs = _joint_ring("LAW", 0.0, ja)
    for i in range(n):
        p0, p1 = cl(i / n), cl((i + 1) / n)
        d = p1 - p0
        ln = d.length
        ax = d.normalized()
        xf = align_y(-ax, p0)   # локальная −Y — вдоль позвонка
        rho = r * (0.86 - 0.4 * i / n)
        objs.append(fin(revolve("LAW_Seg", [(0.0, 0.006), (rho * 0.7, 0.006), (rho, -ln * 0.12), (rho * 0.95, -ln * 0.45),
                                            (rho * 0.64, -ln * 1.03), (0.0, -ln * 1.06)], "League_Flesh", 10, xf), angle=50.0, uv="cyl"))
        objs.append(fin(revolve("LAW_Lip", [(rho * 0.9, 0.009), (rho * 1.1, -ln * 0.03), (rho * 1.06, -ln * 0.2), (rho * 0.94, -ln * 0.22)],
                                "League_Void", 10, xf, closed=True), angle=50.0, uv="cyl"))

        def scute(u, v, xf=xf, rho=rho, ln=ln):
            a = math.radians(60.0) * _scale_w(u) * v
            rr = rho * (1.04 - 0.3 * u) + 0.005 + 0.003 * (1.0 - v * v) ** 2 + 0.006 * u * u
            return xf @ Vector((rr * math.sin(a), -ln * (0.2 + 0.82 * u), rr * math.cos(a)))

        objs.append(_shell("LAW_Scute", scute, "Base_" + base, 0.008, nu=4, nv=6,
                           ref=lambda p, p0=p0, ax=ax: p0 + ax * (p - p0).dot(ax)))
        bend = 1.0 if math.sin((i + 0.5) / n * TAU) >= 0.0 else -1.0
        for sd in (1.0, -1.0):
            k = 1.25 if sd == bend else 0.7
            a0 = Vector((sd * rho * 0.86, -ln * 0.32, 0.0))
            thorn = [a0, a0 + Vector((sd * rho * 0.55 * k, 0.004, 0.0)), a0 + Vector((sd * rho * 0.95 * k, -ln * 0.18, 0.0)),
                     a0 + Vector((sd * rho * 1.1 * k, -ln * 0.45, 0.0))]
            objs += _horn("LAW_Thorn", [xf @ p for p in thorn], rho * 0.3, "Base_" + base, sides=5)
        if i % 2 == 0:
            objs.append(sphere("LAW_Glow", rho * 0.17, tuple(xf @ Vector((0.0, -ln * 0.1, rho * 1.1))), "League_Glow", 8, 4))
    return objs, limb_empties(L, r * 0.8)


# ---------------------------------------------------------------------------------------------------------------------------------
# кисти и стопы (Socket в 0, деталь растёт в −Y)
# ---------------------------------------------------------------------------------------------------------------------------------
def _wrist(prefix, jr, r_cuff):
    """Запястье / лодыжка живой детали: кольцо сустава и хитиновая манжета под шаром."""
    y = -jr * SEG_GAP
    return _joint_ring(prefix, 0.0, jr) + [fin(revolve(prefix + "_Cuff", [(0.0, y - 0.002), (r_cuff * 0.72, y - 0.002), (r_cuff, y - 0.012),
                                                                         (r_cuff * 0.94, y - 0.026), (0.0, y - 0.03)], "League_Void", 10),
                                               angle=40.0, uv="cyl")]


def build_Hand_AoeClaw(base="Bone"):
    """Коготь: алый мышечный узел под хитиновой манжетой, на нём костяной щиток с малым глазом и три длинных костяных когтя-серпа
    со светящейся кромкой — два параллельных (главный и младший) и короткий встречный, как большой палец."""
    _mats()
    objs = _wrist("HAC", 0.044, 0.04)
    c = Vector((0.0, -0.084, 0.0))
    objs.append(_knot("HAC_Knot", 0.04, tuple(c), 0.05))

    def cap(u, v):   # щиток-костяшка на узле, к камере
        lat = math.radians(48.0 - 92.0 * u)
        lon = math.radians(58.0) * _scale_w(u) * v
        return c + Vector((math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon))) * 0.047

    objs.append(_shell("HAC_Cap", cap, "Base_" + base, 0.008, nu=5, nv=4, ref=lambda p: c))
    objs += _eye("HAC_Eye", (0.0, -0.078, 0.046), (0.0, 0.15, 1.0), 0.011, pupil=False)
    for nm, ctrl, w, th, sd in (
            ("HAC_Main", ((0.018, -0.1, 0.0), (0.078, -0.145, 0.0), (0.07, -0.255, 0.0), (-0.004, -0.32, 0.0)), 0.058, 0.018, -1.0),
            ("HAC_Second", ((-0.014, -0.105, 0.018), (0.026, -0.15, 0.02), (0.02, -0.225, 0.022), (-0.034, -0.27, 0.024)), 0.046, 0.016, -1.0),
            ("HAC_Thumb", ((-0.026, -0.09, -0.006), (-0.08, -0.1, -0.006), (-0.094, -0.165, -0.002), (-0.056, -0.21, 0.002)), 0.038, 0.015,
             1.0)):
        objs += _blade(nm, _bezier3(*ctrl, 10), w, th, "Base_" + base, side=sd, taper=0.6)
    return objs, [socket(), shape_box("Hand", (-0.005, -0.15, 0.0), (0.14, 0.2, 0.07))]


def build_Hand_AoeHook(base="Bone"):
    """Крюк-захват: широкий мышечный узел под хитиновой манжетой и пара тяжёлых костяных крюков навстречу друг другу (острия
    почти сходятся — схватить и держать); по внутренней стороне крюков — светящийся шов и по два зубца, снаружи на сгибе —
    костяная шпора, корни крюков перехвачены хитиновыми кольцами."""
    _mats()
    objs = _wrist("HAK", 0.044, 0.042)
    c = Vector((0.0, -0.086, 0.0))
    knot = revolve("HAK_Knot", [(0.0, -0.04)] + [(0.04 * math.sin(math.pi * k / 6), -0.04 * math.cos(math.pi * k / 6)) for k in range(1, 6)]
                   + [(0.0, 0.04)], "League_Flesh", 12, T(c) @ S((1.4, 1.0, 1.0)))
    objs.append(fin(_lumps(knot, tuple(c), 0.05, 60.0), angle=60.0, uv="cyl"))
    n, r0 = 12, 0.024
    for sx in (1, -1):
        pts = _bezier3((sx * 0.034, -0.092, 0.0), (sx * 0.125, -0.085, 0.0), (sx * 0.13, -0.24, 0.0), (sx * 0.012, -0.25, 0.0), n)
        objs += _horn("HAK_Hook", pts, r0, "Base_" + base, sides=8)
        inner = Vector((sx * 0.03, -0.17, 0.0))   # к нему обращена вогнутая сторона крюка
        seam = [pts[i] + (inner - pts[i]).normalized() * (r0 * (1.0 - i / n) ** 0.8) * 0.9 for i in range(3, n - 1)]
        objs.append(sweep("HAK_Seam", seam, 0.0042, "League_Glow", sides=5))
        tg = (pts[3] - pts[1]).normalized()
        rr = r0 * (1.0 - 2 / n) ** 0.8
        objs.append(fin(revolve("HAK_Band", [(rr * 1.02, 0.012), (rr * 1.22, 0.004), (rr * 1.22, -0.006), (rr * 1.02, -0.012)], "League_Void",
                                12, align_y(tg, pts[2]), closed=True), angle=60.0, uv="cyl"))
        objs.append(fin(spike("HAK_Spur", tuple(pts[5] + Vector((sx * 0.012, 0.0, 0.0))), (sx * 0.9, 0.5, 0.0), 0.045, 0.012, "Base_" + base, 6),
                        angle=50.0))
        for i in (7, 9):   # зубцы по вогнутой стороне: держат схваченное
            d = (inner - pts[i]).normalized()
            objs.append(fin(spike("HAK_Tooth", tuple(pts[i] + d * (r0 * (1.0 - i / n) ** 0.8) * 0.6), tuple(d + Vector((0.0, 0.5, 0.0))), 0.026,
                                  0.008, "Base_" + base, 6), angle=50.0))
    return objs, [socket(), shape_box("Hand", (0.0, -0.165, 0.0), (0.23, 0.18, 0.06))]


def build_Foot_AoeStilt(base="Bone"):
    """Ходуля: алый мышечный узел лодыжки в хитиновой манжете и длинный костяной шип-наконечник (ромбическое сечение, плечики с
    двумя зазубринами вверх), по переднему ребру — светящийся шов, от узла к плечикам — две жилы. Длиннее обычной стопы: низ на
    y = −0.23 (у стоп кита — −0.09)."""
    _mats()
    objs = _wrist("FAS", 0.052, 0.04)
    objs.append(_knot("FAS_Knot", 0.035, (0.0, -0.07, 0.0), 0.05))

    def sec(y, hw, ht):
        return [(hw, y, 0.0), (0.0, y, ht), (-hw, y, 0.0), (0.0, y, -ht)]

    st = [(-0.072, 0.016, 0.015), (-0.09, 0.036, 0.023), (-0.11, 0.026, 0.021), (-0.16, 0.018, 0.016), (-0.205, 0.009, 0.009)]
    objs.append(fin(loft("FAS_Spike", [sec(*s) for s in st], "Base_" + base, pole1=(0.0, -0.232, 0.0)), angle=35.0))
    objs.append(sweep("FAS_Seam", [(0.0, -0.096, 0.0236), (0.0, -0.11, 0.0218), (0.0, -0.16, 0.0168), (0.0, -0.198, 0.0108)], 0.0036,
                      "League_Glow", sides=5))
    for sx in (1, -1):
        objs.append(fin(spike("FAS_Barb", (sx * 0.027, -0.093, 0.0), (sx * 0.8, 0.6, 0.0), 0.042, 0.012, "Base_" + base, 6), angle=50.0))
        objs.append(fin(sweep("FAS_Tendon", [(sx * 0.022, -0.062, 0.012), (sx * 0.03, -0.08, 0.014), (sx * 0.024, -0.1, 0.014)],
                              [0.009, 0.008, 0.006], "League_Flesh", sides=6), angle=60.0, uv="cyl"))
    return objs, [socket(), shape_capsule("Foot", (0.0, -0.143, 0.0), 0.024, 0.18)]


def build_Foot_AoeGrip(base="Bone"):
    """Присоска: мышечный узел лодыжки под костяным колпачком и три коротких щупальца-пальца (влево, вправо, к камере), кончики
    закручены вверх; по подошве и завитку — костяные присоски со светящимся дном, на каждом пальце — хитиновое кольцо."""
    _mats()
    objs = _wrist("FAG", 0.052, 0.04)
    c = Vector((0.0, -0.06, 0.0))
    objs.append(_knot("FAG_Knot", 0.036, tuple(c), 0.05))
    cap = [(0.042 * math.sin(math.radians(a)), 0.042 * math.cos(math.radians(a))) for a in (66.0, 44.0, 22.0)] + [(0.0, 0.042)]
    objs.append(fin(revolve("FAG_Cap", cap, "Base_" + base, 12, align_y((0.0, 0.3, 1.0), tuple(c))), angle=50.0))
    n = 10
    for dv in ((1.0, 0.0, 0.2), (-1.0, 0.0, 0.2), (0.0, 0.0, 1.0)):
        d = Vector(dv).normalized()
        pts = _bezier3(c + d * 0.01, c + d * 0.07 - _Y * 0.016, c + d * 0.15 - _Y * 0.012, c + d * 0.1 + _Y * 0.05, n)
        radii = [0.031 - 0.021 * i / n for i in range(n + 1)]
        objs.append(fin(sweep("FAG_Toe", pts, radii, "League_Flesh", sides=10), angle=60.0, uv="cyl"))
        for i in (3, 5, 7, 9):   # присоски — по «подошве» пальца: у завитка она смотрит наружу и вверх
            tg = (pts[i + 1] - pts[i - 1]).normalized()
            under = (d * tg.y - _Y * tg.dot(d)).normalized()
            rho = radii[i] * 0.78
            xf = align_y(under, pts[i] + under * radii[i] * 0.72)
            objs.append(fin(revolve("FAG_Sucker", [(rho * 0.6, 0.0), (rho, 0.003), (rho * 1.04, 0.0085), (rho * 0.62, 0.0105), (rho * 0.34, 0.006)],
                                    "Base_" + base, 8, xf), angle=50.0))
            objs.append(revolve("FAG_SuckerGlow", [(rho * 0.34, 0.0062), (0.0, 0.0075)], "League_Glow", 8, xf))
        tg = (pts[4] - pts[2]).normalized()
        objs.append(fin(revolve("FAG_Ring", [(radii[3] * 1.0, 0.008), (radii[3] * 1.14, 0.0), (radii[3] * 1.0, -0.008)], "League_Void", 10,
                                align_y(tg, pts[3]), closed=True), angle=60.0, uv="cyl"))
    return objs, [socket(), shape_box("Foot", (0.0, -0.073, 0.03), (0.26, 0.05, 0.18))]


# ---------------------------------------------------------------------------------------------------------------------------------
# броня и декор (attach fixed: формы переезжают в тело-хозяина)
# ---------------------------------------------------------------------------------------------------------------------------------
def build_Deco_AoeCarapace(base="Bone", r=0.058):
    """Панцирь на конечность (Anchor_Deco): алая мышечная подкладка-рукав, хитиновый ворот со светящимся швом и два ряда костяных
    чешуй внахлёст (верхний ряд накрывает нижний, острия отогнуты наружу, по середине — киль, в кости — алые поры); в просветах
    верхнего ряда — светящиеся точки. r — радиус конечности (0.058 рука, 0.074 нога)."""
    _mats()
    R = r * 1.32
    y0 = -0.042
    h = r * 2.9
    objs = [fin(revolve("DAC_Lining", [(R - 0.012, y0), (R - 0.005, y0 - 0.004), (R - 0.003, y0 - h * 0.5), (R - 0.006, y0 - h * 0.88),
                                       (R - 0.012, y0 - h * 0.86)], "League_Flesh", 20, closed=True), angle=60.0, uv="cyl")]
    objs.append(fin(revolve("DAC_Collar", [(R - 0.01, y0 + 0.012), (R + 0.009, y0 + 0.006), (R + 0.011, y0 - 0.012), (R - 0.004, y0 - 0.016)],
                            "League_Void", 20, closed=True), angle=50.0, uv="cyl"))
    objs.append(torus("DAC_Seam", (0.0, y0 - 0.016, 0.0), R + 0.006, 0.0036, "League_Glow", 'XZ', 24, 5))
    for k in range(4):   # верхний ряд: четыре чешуи, передняя — чуть к внешней стороне
        fn = _limb_plate(y0 - 0.01, y0 - h * 0.66, lambda y: R + 0.003, 20.0 + 90.0 * k, 54.0, 0.012, 0.004, r * 0.12)
        objs.append(_shell("DAC_ScaleA", fn, "Base_" + base, 0.009, nu=6, nv=6))
        objs += _pores("DAC_Pit", [fn(0.28, 0.42), fn(0.5, -0.36)], r * 0.11)
        a = math.radians(65.0 + 90.0 * k)
        objs.append(sphere("DAC_Pore", 0.0065, ((R - 0.001) * math.sin(a), y0 - h * 0.5, (R - 0.001) * math.cos(a)), "League_Glow", 8, 4))
    for k in range(4):   # нижний ряд — в шахматном порядке, под верхним
        fn = _limb_plate(y0 - h * 0.4, y0 - h, lambda y: R - 0.003, 65.0 + 90.0 * k, 48.0, 0.014, 0.004, r * 0.1)
        objs.append(_shell("DAC_ScaleB", fn, "Base_" + base, 0.009, nu=5, nv=6))
    return objs, [socket(), shape_cyl("Carapace", (0.0, y0 - h / 2, 0.0), R + 0.016, h)]


def build_Deco_AoeSpines(base="Bone"):
    """Спинные иглы (Anchor_Back ядра или Anchor_Top головы): хитиновое седло-основание и веер из пяти костяных игл разной длины
    (средняя — самая длинная, крайние — короткие и сильнее отклонены), все чуть загнуты назад; у корня каждой — алый мышечный узел
    и светящееся кольцо."""
    _mats()
    arch = [Vector((x, 0.012 - 1.9 * x * x, -0.004)) for x in (-0.1, -0.07, -0.035, 0.0, 0.035, 0.07, 0.1)]
    objs = [fin(sweep("DAS_Base", arch, [0.012, 0.02, 0.024, 0.026, 0.024, 0.02, 0.012], "League_Void", sides=8), angle=60.0, uv="cyl")]
    for x, ln, lean in ((0.0, 0.25, 0.0), (0.04, 0.21, 22.0), (-0.04, 0.21, -22.0), (0.078, 0.16, 46.0), (-0.078, 0.16, -46.0)):
        root = Vector((x, 0.014 - 1.9 * x * x, -0.004))
        d = Vector((math.sin(math.radians(lean)), math.cos(math.radians(lean)), 0.0))
        pts = _bezier3(root, root + d * ln * 0.35 + _Z * 0.012, root + d * ln * 0.72 - _Z * 0.012, root + d * ln - _Z * 0.07, 8)
        objs += _horn("DAS_Spine", pts, 0.019, "Base_" + base, sides=7)
        objs.append(_knot("DAS_Knot", 0.024, tuple(root + d * 0.006), 0.06, 8, 4))
        objs.append(revolve("DAS_Glow", [(0.0165, 0.0034), (0.0215, 0.0), (0.0165, -0.0034)], "League_Glow", 12,
                            align_y(d, root + d * 0.034), closed=True))
    return objs, [socket(rot_z=180.0), _back_box("Base", 0.0, 0.06, 0.34, 0.14), _back_box("Crest", 0.0, 0.19, 0.2, 0.14)]


# ---------------------------------------------------------------------------------------------------------------------------------
# разветвители (04.10, «невозможные конструкции»): живые детали с тремя разъёмами — щупальце делится, хребет обрастает ногами.
# Имена якорей — из контракта (End, Side_L / Side_R), как у тройника и рамы-позвонка про-лиги (kit_pro.py).
# ---------------------------------------------------------------------------------------------------------------------------------
def _stump(prefix, center, d, r0, r1, rc=0.036):
    """Живой отросток-разъём: мышечный пенёк от центра узла по направлению d и хитиновая манжета на торце."""
    c, d = Vector(center), Vector(d)
    xf = align_y(d, c + d * r0)
    h = r1 - r0
    return [fin(revolve(prefix + "_Stump", [(0.0, 0.0), (rc * 1.05, 0.0), (rc * 0.9, h * 0.6), (rc * 0.8, h), (0.0, h)], "League_Flesh", 12,
                        xf), angle=60.0, uv="cyl"),
            fin(revolve(prefix + "_StumpCuff", [(rc * 0.84, h - 0.02), (rc * 1.12, h - 0.014), (rc * 1.12, h - 0.004), (rc * 0.84, h)],
                        "League_Void", 12, xf, closed=True), angle=50.0, uv="cyl")]


NODE_C = (0.0, -0.105, 0.0)    # центр живого узла
NODE_D = 0.088                 # от центра до якоря
NODE_FAN = 70.0


def build_Hub_AoeNode(base="Bone"):
    """Узел-сплетение — живой разветвитель: кольцо сустава и хитиновая манжета, бугристый мышечный узел, на нём три костяные
    пластины-лепестка (спереди и по плечам) и светящийся глаз; три мышечных отростка с хитиновыми манжетами — вниз и в стороны
    на ±70°. Щупальце, вставшее в узел, расходится в три."""
    _mats()
    c = Vector(NODE_C)
    R = 0.06
    objs = _wrist("HAN", 0.052, 0.04)
    objs.append(fin(revolve("HAN_Neck", [(0.0, -0.04), (0.03, -0.04), (0.034, -0.062), (0.0, -0.062)], "League_Flesh", 12), uv="cyl"))
    objs.append(_knot("HAN_Knot", R, tuple(c), amp=0.06, segs=16, rings=8))
    objs += _eye("HAN", c + Vector((0.0, 0.004, R * 0.92)), (0.0, 0.0, 1.0), 0.018)
    # костяные лепестки: один над глазом и два на «плечах» узла
    for k, (ax, ay) in enumerate(((0.0, 0.62), (0.7, 0.3), (-0.7, 0.3))):
        d = Vector((ax, ay, 0.62)).normalized()
        xf = align_y(d, c + d * (R - 0.004))
        objs.append(fin(revolve("HAN_Plate%d" % k, [(0.0, 0.0), (0.03, 0.0), (0.026, 0.008), (0.012, 0.014), (0.0, 0.015)],
                                "Base_" + base, 10, xf), 0.002, 1, angle=50.0, uv="cyl"))
    empties = [socket(), shape_sphere("Hub", tuple(c), R + 0.012)]
    for nm, deg in (("End", 0.0), ("Side_L", NODE_FAN), ("Side_R", -NODE_FAN)):
        a = math.radians(deg)
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        objs += _stump("HAN_" + nm, c, d, R - 0.014, NODE_D - 0.028)
        empties.append(anchor(nm, tuple(c + d * NODE_D), deg))
    return objs, empties


def build_Limb_AoeSpine(L=0.30, r=0.058, ja=0.064, jb=0.054, base="Bone"):
    """Позвонок — живое звено с двумя боковыми отростками: мышечный пучок между хитиновыми манжетами, посередине костяной
    позвонок (кольцо с гребнем к камере и остистым шипом назад), из него вбок — два мышечных отростка-разъёма с манжетами.
    Цепочка позвонков — хребет: на каждом пара ног, лезвий или щупалец."""
    _mats()
    y0, y1 = -ja * SEG_GAP, -L + jb * SEG_GAP
    ya, h = y0 - 0.014, y0 - y1 - 0.028
    ym = (y0 + y1) / 2.0

    def rad(y):
        return r * (0.5 + 0.3 * math.sin(math.pi * min(max((ya - y) / h, 0.0), 1.0)) ** 0.7)

    objs = _joint_ring("LAV", 0.0, ja) + _cuffs("LAV", y0, y1, r)
    n = 10
    pts = [Vector((0.0, ya - h * i / n, 0.0)) for i in range(n + 1)]
    objs += _sinew("LAV_Sinew", pts, [rad(p.y) for p in pts], strands=4, twist=0.9)
    # костяной позвонок: кольцо вокруг пучка, гребень вперёд, шип назад
    rv = rad(ym) * 1.12 + 0.006
    hv = min(0.05, h * 0.22)
    objs.append(fin(revolve("LAV_Vert", [(rv * 0.86, ym + hv), (rv * 1.12, ym + hv * 0.6), (rv * 1.18, ym), (rv * 1.12, ym - hv * 0.6),
                                         (rv * 0.86, ym - hv)], "Base_" + base, 14, closed=True), 0.002, 1, angle=50.0, uv="cyl"))
    objs += _horn("LAV_Keel", [Vector((0.0, ym + hv * 0.4, rv * 1.05)), Vector((0.0, ym + hv * 0.9, rv * 1.5)),
                               Vector((0.0, ym + hv * 1.9, rv * 1.75))], r * 0.2, mat="Base_" + base, sides=6)
    objs += _horn("LAV_Spur", [Vector((0.0, ym, -rv * 1.05)), Vector((0.0, ym - hv * 0.5, -rv * 1.7)),
                               Vector((0.0, ym - hv * 1.6, -rv * 2.3))], r * 0.22, mat="Base_" + base, sides=6, tip="League_Glow")
    for t, deg in ((0.16, 50.0), (0.84, -50.0)):
        y = ya - h * t
        a = math.radians(deg)
        objs.append(sphere("LAV_Glow", r * 0.11, (rad(y) * 1.02 * math.sin(a), y, rad(y) * 1.02 * math.cos(a)), "League_Glow", 8, 4))
    D = rv * 1.18 + 0.062
    empties = limb_empties(L, r)
    for nm, sx in (("Side_L", 1.0), ("Side_R", -1.0)):
        d = Vector((sx, 0.0, 0.0))
        objs += _stump("LAV_" + nm, (0.0, ym, 0.0), d, rv * 1.0, D - 0.028, rc=0.034)
        empties.append(anchor(nm, (sx * D, ym, 0.0), sx * 90.0))
    empties.append(shape_box("Ribs", (0.0, ym, 0.0), ((D - 0.03) * 2.0, r * 1.1, r * 1.1)))
    return objs, empties


META = {
    "Hub_AoeNode": {"kind": "joint", "title": "Узел-сплетение", "mass": 2.2, "energy": 4},
    "Limb_AoeSpine": {"kind": "limb", "title": "Позвонок", "mass": {"S": 2.0, "L": 3.7}, "energy": {"S": 6, "L": 8}},
    "Core_AoeHeart": {"kind": "core", "title": "Ядро-сердце", "mass": 13.0, "energy": 0},
    "Head_AoeWatcher": {"kind": "head", "title": "Голова-наблюдатель", "mass": 4.0, "energy": 10, "hit_mult": 1.1},
    "Head_AoeHunter": {"kind": "head", "title": "Голова-охотник", "mass": 4.4, "energy": 11, "hit_mult": 1.15},
    "Limb_AoeSinew": {"kind": "limb", "title": "Жила", "mass": {"S": 1.8, "L": 3.4}, "energy": {"S": 5, "L": 7}},
    "Limb_AoeBlade": {"kind": "limb", "title": "Лезвия", "mass": {"S": 2.3, "L": 4.4}, "energy": {"S": 7, "L": 9}, "hit_mult": 1.2},
    "Limb_AoeWhip": {"kind": "limb", "title": "Плеть", "mass": {"S": 1.5, "L": 2.9}, "energy": {"S": 5, "L": 7}, "hit_mult": 1.1},
    "Hand_AoeClaw": {"kind": "hand", "title": "Коготь", "mass": 1.0, "energy": 4, "hit_mult": 1.2},
    "Hand_AoeHook": {"kind": "hand", "title": "Крюк-захват", "mass": 1.1, "energy": 4, "hit_mult": 1.1},
    "Foot_AoeStilt": {"kind": "foot", "title": "Ходуля", "mass": 0.8, "energy": 3, "hit_mult": 1.15},
    "Foot_AoeGrip": {"kind": "foot", "title": "Присоска", "mass": 0.7, "energy": 3},
    "Deco_AoeCarapace": {"kind": "armor", "title": "Панцирь", "mass": {"S": 1.2, "L": 1.8}, "energy": 4},
    "Deco_AoeSpines": {"kind": "deco", "title": "Спинные иглы", "mass": 0.7, "energy": 2, "body_mult": 1.15},
}
