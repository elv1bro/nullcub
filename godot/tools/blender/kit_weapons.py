"""Оружейные детали кита (дополнение к craft_parts.py: наконечники, бур, пила…). Контракт — как у головок craft_parts:
Socket в центре проушины, рукоять входит на 3.5 см глубже якоря (торец прячет железная обойма), над Socket — стальная
проушина для цепи; деталь растёт в −Y; Face_L / Face_R — бойки (L = +X, R = −X; −X при махе по часовой — передний)."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


def _collar(prefix, y_bot, r=0.034, stripe=None):
    """Железная обойма под торец рукояти (y 0.012 → y_bot) с заклёпками, стальная проушина над Socket (на цепи в неё продето
    звено, на рукояти её прячет древко), stripe — y полоски цвета игрока на обойме."""
    objs = ferrule(prefix + "_Collar", 0.012, y_bot, r, "Iron", 4)
    objs.append(fin(torus(prefix + "_Eye", (0.0, 0.004, 0.0), 0.016, 0.0055, "Steel", 'XY', 12, 6), angle=80))
    if stripe is not None:   # как kit_common.band, но 16 сегментов без фаски — бюджет треугольников
        rr, h = r * 1.07, 0.014
        objs.append(fin(revolve(prefix + "_Stripe", [(rr * 0.97, stripe + h / 2), (rr, stripe + h * 0.3), (rr, stripe - h * 0.3),
                                                     (rr * 0.97, stripe - h / 2)], "Shirt_Kit", 16, closed=True), uv="cyl"))
    return objs


def _lerp_profile(prof, y):
    """Радиус тела вращения prof [(r, y), …] (y убывает) на высоте y — для спиралей по конусу."""
    for (r0, y0), (r1, y1) in zip(prof, prof[1:]):
        if y1 <= y <= y0 and y0 != y1:
            return r0 + (r1 - r0) * (y0 - y) / (y0 - y1)
    return prof[-1][0]


def build_Spear_Tip(base="Iron"):
    """Наконечник копья: обойма с заклёпками и полоской, кованая втулка, листовидное перо с ребром жёсткости."""
    objs = _collar("SP", -0.085, stripe=-0.064)
    neck = [(0.0, -0.06), (0.03, -0.06), (0.03, -0.086), (0.026, -0.1), (0.019, -0.118), (0.015, -0.132), (0.0, -0.14)]
    objs.append(fin(revolve("SP_Neck", neck, "Base_" + base, 16), 0.002, 1, uv="cyl"))
    objs.append(fin(torus("SP_NeckRing", (0.0, -0.1, 0.0), 0.027, 0.005, "Iron", 'XZ', 16, 6), angle=80))

    def section(y, hw, t):
        rw, tf = min(0.012, 0.35 * hw), 0.45 * t
        return [(hw, y, 0.0), (rw, y, tf), (0.0, y, t), (-rw, y, tf), (-hw, y, 0.0), (-rw, y, -tf), (0.0, y, -t), (rw, y, -tf)]

    st = [(-0.118, 0.016, 0.013), (-0.14, 0.033, 0.013), (-0.17, 0.048, 0.012), (-0.21, 0.057, 0.011), (-0.26, 0.059, 0.010),
          (-0.31, 0.053, 0.009), (-0.36, 0.04, 0.007), (-0.40, 0.025, 0.005), (-0.43, 0.011, 0.003)]
    blade = loft("SP_Blade", [section(y, hw, t) for y, hw, t in st], "Base_" + base, pole1=(0.0, -0.455, 0.0))
    objs.append(fin(blade, angle=30.0))
    empties = [socket(), shape_box("Collar", (0.0, -0.036, 0.0), (0.072, 0.098, 0.072)),
               shape_box("Neck", (0.0, -0.11, 0.0), (0.05, 0.05, 0.06)),
               shape_box("Blade", (0.0, -0.29, 0.0), (0.118, 0.33, 0.06))]
    return objs, empties


def build_Drill_Head(base="Iron"):
    """Бур: обойма, латунный патрон с болтами, конус с двумя спиральными гребнями (двойная винтовая нарезка)."""
    objs = _collar("DR", -0.07, stripe=-0.052)
    chuck = [(0.0, -0.055), (0.04, -0.055), (0.058, -0.068), (0.064, -0.08), (0.064, -0.13), (0.058, -0.14), (0.05, -0.146), (0.0, -0.146)]
    objs.append(fin(revolve("DR_Chuck", chuck, "Brass", 22), 0.002, 1, uv="cyl"))
    objs.append(band("DR_ChuckBand", -0.105, 0.066, 0.016, "Iron"))
    objs += ring_rivets("DR_ChuckBolt", -0.105, 0.067, 3, "Steel", 0.009, phase=math.pi / 2)
    cone = [(0.0, -0.14), (0.056, -0.14), (0.06, -0.15), (0.058, -0.16), (0.046, -0.21), (0.034, -0.27), (0.022, -0.33),
            (0.012, -0.38), (0.005, -0.415), (0.0, -0.43)]
    objs.append(fin(revolve("DR_Cone", cone, "Base_" + base, 20), 0.0, uv="cyl", angle=50.0))
    for k in range(2):
        pts, radii = [], []
        for i in range(44):
            t = i / 43
            y = -0.158 - 0.245 * t
            a = math.pi * k + TAU * 2.25 * t
            rc = _lerp_profile(cone, y) * 0.96
            pts.append((rc * math.cos(a), y, rc * math.sin(a)))
            radii.append(0.011 * (1.0 - t) + 0.0022)
        objs.append(fin(sweep("DR_Flute%d" % k, pts, radii, "Base_" + base, sides=6), angle=70))
    empties = [socket(), shape_box("Collar", (0.0, -0.03, 0.0), (0.07, 0.09, 0.07)),
               shape_cyl("Chuck", (0.0, -0.1, 0.0), 0.064, 0.092), shape_cyl("Base", (0.0, -0.18, 0.0), 0.055, 0.07),
               shape_capsule("Bit", (0.0, -0.3, 0.0), 0.034, 0.25)]
    return objs, empties


def _saw_outline(cy, r_root, r_tip, teeth):
    """Контур пильного диска: зуб — пологий подъём к вершине и крутой спуск во впадину (как у циркулярной пилы)."""
    step = TAU / teeth
    pts = []
    for i in range(teeth):
        a = i * step
        for f, r in ((0.0, r_root), (0.55, r_root + (r_tip - r_root) * 0.5), (0.86, r_tip), (0.92, r_root - 0.008)):
            pts.append((r * math.cos(a + f * step), cy + r * math.sin(a + f * step)))
    return pts


def build_Saw_Disc(base="Iron"):
    """Дисковая пила: обойма, железная вилка на заклёпках, диск с 24 зубьями на латунной ступице и стальной оси."""
    yh = -0.24
    objs = _collar("SD", -0.07, stripe=-0.052)
    objs.append(fin(extrude2d("SD_Disc", _saw_outline(yh, 0.126, 0.15, 24), -0.004, 0.004, "Base_" + base), 0.0015, 1, angle=40))
    for sz in (1, -1):
        objs.append(fin(torus("SD_Rib", (0.0, yh, sz * 0.004), 0.098, 0.0028, "Iron", 'XY', 32, 4), angle=80))
        objs.append(rbox("SD_Fork", (0.032, 0.215, 0.008), "Iron", (0.0, -0.152, sz * 0.02), 0.003, 1))
        objs.append(fin(stud("SD_ForkRivet", (0.0, -0.085, sz * 0.024), (0, 0, sz), "Steel", 0.007, 0.004, 6)))
        objs.append(fin(stud("SD_Nut", (0.0, yh, sz * 0.024), (0, 0, sz), "Steel", 0.015, 0.009, 6)))
    hub = [(0.0, -0.016), (0.03, -0.016), (0.038, -0.009), (0.038, 0.009), (0.03, 0.016), (0.0, 0.016)]
    objs.append(fin(revolve("SD_Hub", hub, "Brass", 18, T((0.0, yh, 0.0)) @ Rx(90.0)), 0.002, 1, uv="cyl", axis='Z'))
    objs.append(fin(revolve("SD_Axle", [(0.0, -0.03), (0.008, -0.03), (0.008, 0.03), (0.0, 0.03)], "Steel", 10,
                            T((0.0, yh, 0.0)) @ Rx(90.0)), 0.001, 1, uv="cyl", axis='Z'))
    empties = [socket(), shape_box("Collar", (0.0, -0.03, 0.0), (0.07, 0.09, 0.07)),
               shape_box("Fork", (0.0, -0.15, 0.0), (0.05, 0.16, 0.06)), shape_sphere("Disc", (0.0, yh, 0.0), 0.148)]
    return objs, empties


def build_Pick_Head(base="RustRed"):
    """Кирка-молоток: крашеная проушина с болтами и клином, клюв со стальным остриём загнут к хвату (−X, передний),
    боёк со стальным торцом и полоской цвета игрока (+X, Face_L — сюда встают моды)."""
    objs = [rbox("PK_Eye", (0.074, 0.112, 0.066), "Base_" + base, (0.0, 0.0, 0.0), 0.014, 2)]
    objs.append(fin(box("PK_Wedge", (0.014, 0.008, 0.05), "Steel", (0.0, -0.058, 0.0)), 0.002, 1))
    for sz in (1, -1):
        for y in (0.03, -0.03):
            objs.append(fin(stud("PK_Bolt", (0.0, y, sz * 0.033), (0, 0, sz), "Steel", 0.009, 0.005, 6)))

    def arm(t):
        return (-0.03 - 0.205 * t, 0.07 * t * t, 0.0)

    def rad(t):
        return 0.028 * (1.0 - t / 1.1) ** 0.8 + 0.0012

    ts = [0.72 * i / 7 for i in range(8)]
    objs.append(fin(sweep("PK_Arm", [arm(t) for t in ts], [rad(t) for t in ts], "Base_" + base, sides=8), angle=55))
    ts = [0.66 + 0.44 * i / 6 for i in range(7)]
    objs.append(fin(sweep("PK_Tip", [arm(t) for t in ts], [rad(t) * (1.06 if t < 1.05 else 1.0) for t in ts], "Steel", sides=8),
                    angle=55))
    poll = [(0.0, 0.03), (0.03, 0.03), (0.027, 0.07), (0.026, 0.085), (0.033, 0.095), (0.034, 0.118), (0.031, 0.124), (0.0, 0.124)]
    objs.append(fin(revolve("PK_Poll", poll, "Base_" + base, 20, Rz(-90.0)), 0.002, 1, uv="cyl", axis='X'))
    objs.append(fin(revolve("PK_Face", [(0.0, 0.12), (0.031, 0.12), (0.03, 0.128), (0.02, 0.1325), (0.0, 0.1335)], "Steel", 20, Rz(-90.0)),
                    0.001, 1, uv="cyl", axis='X'))
    objs.append(fin(revolve("PK_Stripe", [(0.0283, 0.069), (0.0298, 0.066), (0.0298, 0.054), (0.0283, 0.051)], "Shirt_Kit", 20, Rz(-90.0),
                            closed=True), 0.0, uv="cyl", axis='X'))
    empties = [socket(), anchor("Face_L", (0.1335, 0.0, 0.0), 90.0),
               shape_box("Eye", (0.0, 0.0, 0.0), (0.076, 0.114, 0.066)), shape_box("Poll", (0.08, 0.0, 0.0), (0.1, 0.068, 0.068)),
               shape_box("Pick", (-0.14, 0.035, 0.0), (0.24, 0.05, 0.06), -20.0)]
    return objs, empties


def _flame_ring(y, r, cx, twist, n=16):
    """Кольцо языка пламени: три лепестка (r·(1 + 0.2·cos 3θ)), закрученные по высоте, центр гуляет по X."""
    out = []
    for k in range(n):
        th = TAU * k / n
        rr = r * (1.0 + 0.2 * math.cos(3.0 * th + twist))
        out.append((cx + rr * math.cos(th), y, rr * math.sin(th)))
    return out


def build_Torch_Head(base="Wood"):
    """Факел («огонь» на листе автора): обойма, связка из семи палок на верёвках, железная корзинка со смолой и
    светящееся закрученное пламя (CoreGlow) с тремя языками."""
    objs = _collar("TH", -0.06, stripe=-0.044)
    for k in range(7):
        if k == 6:
            a0, a1 = Vector((0.0, -0.04, 0.0)), Vector((0.0, -0.228, 0.0))
            rr = 0.012
        else:
            a = TAU * k / 6 + 0.2
            d = Vector((math.cos(a), 0.0, math.sin(a)))
            a0, a1 = Vector((0.0, -0.04, 0.0)) + d * 0.017, Vector((0.0, -0.228, 0.0)) + d * 0.026
            rr = 0.0105
        objs.append(fin(sweep("TH_Stave", [a0, (a0 + a1) / 2, a1], [rr * 0.95, rr, rr * 0.9], "Base_" + base, sides=6), angle=50, uv="cyl"))
    objs += K.wrap_rings("TH_Wrap", -0.078, -0.09, 2, 0.03, 0.0055, 12.0)
    objs += K.wrap_rings("TH_WrapB", -0.172, -0.184, 2, 0.037, 0.0055, 12.0)
    objs.append(fin(sphere("TH_Tar", 0.047, (0.0, -0.262, 0.0), "Rubber", 16, 8), angle=70))
    objs.append(fin(torus("TH_CageTop", (0.0, -0.222, 0.0), 0.039, 0.0065, "Iron", 'XZ', 18, 6), angle=80))
    objs.append(fin(torus("TH_CageRim", (0.0, -0.305, 0.0), 0.05, 0.006, "Iron", 'XZ', 20, 6), angle=80))
    for k in range(4):
        a = TAU * k / 4 + math.pi / 4
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        pts = [Vector((0.0, y, 0.0)) + d * r for y, r in ((-0.222, 0.039), (-0.245, 0.055), (-0.272, 0.061), (-0.3, 0.052), (-0.305, 0.05))]
        objs.append(fin(sweep("TH_CageBar", pts, 0.0055, "Iron", sides=6), angle=70))
    prof = [(0.0, 0.036), (0.12, 0.052), (0.25, 0.056), (0.4, 0.05), (0.55, 0.04), (0.7, 0.028), (0.84, 0.016), (0.94, 0.007)]
    y0, L = -0.255, 0.225
    rings = [_flame_ring(y0 - L * t, r, 0.018 * math.sin(t * 2.0 * math.pi) * t, t * 2.2 * math.pi) for t, r in prof]
    objs.append(fin(loft("TH_Flame", rings, "CoreGlow", pole0=(0.0, y0 + 0.01, 0.0), pole1=(-0.004, y0 - L, 0.0)), angle=70))
    tongues = (   # языки: левый длинный, правый короткий с загибом наружу, передний — объём при взгляде сбоку
        [(-0.03, -0.28, 0.01), (-0.06, -0.315, 0.012), (-0.07, -0.355, 0.01), (-0.06, -0.392, 0.006), (-0.04, -0.418, 0.003)],
        [(0.03, -0.285, 0.008), (0.062, -0.315, 0.01), (0.074, -0.345, 0.008), (0.07, -0.37, 0.004), (0.058, -0.388, 0.002)],
        [(0.0, -0.285, 0.03), (0.01, -0.32, 0.052), (0.004, -0.355, 0.05), (-0.008, -0.38, 0.036)])
    for i, pts in enumerate(tongues):
        radii = [0.021, 0.017, 0.011, 0.006, 0.0012][-len(pts):] if i < 2 else [0.018, 0.013, 0.007, 0.0012]
        objs.append(fin(sweep("TH_Tongue", pts, radii, "CoreGlow", sides=8), angle=70))
    empties = [socket(), shape_box("Collar", (0.0, -0.025, 0.0), (0.07, 0.075, 0.07)),
               shape_cyl("Bundle", (0.0, -0.15, 0.0), 0.037, 0.18), shape_sphere("Fire", (0.0, -0.29, 0.0), 0.066)]
    return objs, empties


def build_Anchor_Head(base="Iron"):
    """Якорь-адмиралтейский (⚓): обойма, веретено с верёвочной обмоткой, шток с шарами, дуга рогов с лапами-стрелками —
    тяжёлый и цепляющийся."""
    objs = _collar("AN", -0.07, stripe=-0.052)
    shank = [(0.0, -0.06), (0.024, -0.06), (0.022, -0.1), (0.023, -0.2), (0.026, -0.3), (0.03, -0.35), (0.0, -0.36)]
    objs.append(fin(revolve("AN_Shank", shank, "Base_" + base, 14), 0.0, uv="cyl"))
    objs.append(fin(sweep("AN_Stock", [(-0.1, -0.105, 0.0), (0.0, -0.105, 0.0), (0.1, -0.105, 0.0)], 0.013, "Base_" + base, sides=10),
                    angle=60, axis='X'))
    for sx in (-1, 1):
        objs.append(fin(sphere("AN_StockBall", 0.021, (sx * 0.106, -0.105, 0.0), "Base_" + base, 14, 7), angle=80))
    objs += K.wrap_rings("AN_Rope", -0.14, -0.178, 3, 0.03, 0.0055, 12.0)
    objs.append(fin(sphere("AN_Crown", 0.034, (0.0, -0.36, 0.0), "Base_" + base, 16, 8), angle=70))
    c, R = Vector((0.0, -0.245, 0.0)), 0.12
    pts, radii = [], []
    for i in range(15):
        a = math.radians(-155.0 + 130.0 * i / 14)
        pts.append(c + Vector((math.cos(a), math.sin(a), 0.0)) * R)
        radii.append(0.0195 - 0.006 * abs(i - 7) / 7)
    objs.append(fin(sweep("AN_Arms", pts, radii, "Base_" + base, sides=10), angle=60))
    fluke = [(0.074, 0.0), (0.012, 0.042), (-0.022, 0.03), (-0.008, 0.0), (-0.022, -0.03), (0.012, -0.042)]
    shapes = []
    for sx, deg in ((1, -25.0), (-1, -155.0)):
        a = math.radians(deg)
        end = c + Vector((math.cos(a), math.sin(a), 0.0)) * R
        tan = Vector((-math.sin(a), math.cos(a), 0.0)) * sx
        nrm = Vector((-tan.y, tan.x, 0.0))
        outline = [tuple((end + tan * u + nrm * v).xy) for u, v in fluke]
        objs.append(fin(extrude2d("AN_Fluke", outline, -0.011, 0.011, "Base_" + base), 0.003, 1, angle=45))
        side = "L" if sx > 0 else "R"
        shapes.append(shape_box("Fluke_" + side, tuple(end + tan * 0.026), (0.1, 0.075, 0.06), math.degrees(math.atan2(tan.y, tan.x))))
        shapes.append(shape_box("Arm_" + side, (sx * 0.058, -0.338, 0.0), (0.14, 0.06, 0.06), sx * 32.0))
    empties = [socket(), shape_box("Collar", (0.0, -0.03, 0.0), (0.07, 0.09, 0.07)), shape_box("Shank", (0.0, -0.21, 0.0), (0.05, 0.3, 0.06)),
               shape_box("Stock", (0.0, -0.105, 0.0), (0.254, 0.042, 0.06))] + shapes
    return objs, empties


# Метаданные для kit_catalog.json: вид weapon_head / handle / mod (fixed), weapon_mult — множитель урона оружия (как craft_parts:
# клинок 1.6, топор 1.3, гвозди 1.25, тупое 1.0), энергия 0 (оружейные детали энергии тела не тратят); name_prefix — как в
# build_craft_parts.gd (Blade — режет/колет, Hammer — боёк, Hook — цепляет, Mace — тупое)
META = {
    "Spear_Tip": {"kind": "weapon_head", "title": "Наконечник копья", "mass": 0.9, "energy": 0, "weapon_mult": 1.5,
                  "name_prefix": "Blade"},
    "Drill_Head": {"kind": "weapon_head", "title": "Бур", "mass": 2.4, "energy": 0, "weapon_mult": 1.45, "name_prefix": "Blade"},
    "Saw_Disc": {"kind": "weapon_head", "title": "Дисковая пила", "mass": 1.8, "energy": 0, "weapon_mult": 1.55, "name_prefix": "Blade"},
    "Pick_Head": {"kind": "weapon_head", "title": "Кирка", "mass": 2.6, "energy": 0, "weapon_mult": 1.35, "name_prefix": "Hammer"},
    "Torch_Head": {"kind": "weapon_head", "title": "Факел", "mass": 0.9, "energy": 0, "weapon_mult": 1.2, "name_prefix": "Mace"},
    "Anchor_Head": {"kind": "weapon_head", "title": "Якорь", "mass": 3.2, "energy": 0, "weapon_mult": 1.1, "name_prefix": "Hook"},
}
