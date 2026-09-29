"""Кисти и стопы кита (концевые детали: Socket в 0, без Anchor_End). Кисть растёт от запястья в −Y на 0.15–0.24 м, манжет —
ferrule(); стопа: Socket на лодыжке, низ подошвы на y = −0.09 (высота лодыжки рига v3), носок к камере (+Z), как у ботинка.
Шар сустава (JOINT_R Wrist 0.044 / Ankle 0.052) закрывает всё, что ближе к Socket, — читаемое ставим ниже или впереди него."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


def _dome(name, r, center, mat, sy=1.0, segs=20, rings=10):
    """Сфера, сплюснутая по Y (sy < 1): колпак носка, костяшки."""
    prof = ([(0.0, -r * sy)] + [(r * math.sin(math.pi * k / rings), -r * sy * math.cos(math.pi * k / rings)) for k in range(1, rings)]
            + [(0.0, r * sy)])
    return revolve(name, prof, mat, segs, T(center))


def _zrev(name, prof, mat, center, segs=24, closed=False):
    """Тело вращения вокруг оси Z (к камере): prof [(r, z)] от центра — колесо, шина, ось."""
    return revolve(name, prof, mat, segs, T(center) @ Rx(90.0), closed=closed)


def _bezier(a, b, c, n):
    """n + 1 точек квадратичной кривой a → c с контрольной b (пальцы клешни)."""
    a, b, c = Vector(a), Vector(b), Vector(c)
    return [a * (1 - t) ** 2 + b * 2 * t * (1 - t) + c * t * t for t in (i / n for i in range(n + 1))]


def build_Hand_Mitten(base="Wood"):
    """Кисть-варежка: железный манжет, пухлая ладонь, большой палец к камере, ремешок цвета игрока."""
    objs = ferrule("HM_Cuff", -0.012, -0.05, 0.046)
    objs.append(rbox("HM_Palm", (0.105, 0.125, 0.07), "Base_" + base, (0.0, -0.115, 0.0), 0.032, 3))
    thumb = [(0.03, -0.075, 0.022), (0.05, -0.1, 0.045), (0.052, -0.13, 0.05)]
    objs.append(fin(sweep("HM_Thumb", thumb, [0.022, 0.021, 0.018], "Base_" + base, sides=12), angle=70))
    objs.append(fin(sphere("HM_ThumbTip", 0.018, thumb[-1], "Base_" + base, 12, 6), angle=80))
    objs.append(rbox("HM_Strap", (0.112, 0.022, 0.076), "Shirt_Kit", (0.0, -0.085, 0.0), 0.008, 2))
    objs.append(fin(stud("HM_Buckle", (0.0, -0.085, 0.039), (0, 0, 1), "Brass", 0.01, 0.006, 4)))
    return objs, [socket(), shape_box("Hand", (0.0, -0.11, 0.0), (0.1, 0.14, 0.07))]


def build_Hand_Claw(base="Iron"):
    """Клешня: манжет, литой корпус, три крючковатых стальных пальца на шарах-костяшках (крайние загнуты внутрь,
    средний — к камере), ось поперёк."""
    objs = ferrule("HCl_Cuff", -0.012, -0.05, 0.046)
    objs.append(rbox("HCl_Body", (0.09, 0.06, 0.07), "Base_" + base, (0.0, -0.075, 0.0), 0.018, 2))
    for sx in (-1, 0, 1):
        root = (sx * 0.03, -0.1, 0.0 if sx else 0.012)
        if sx:
            pts = _bezier(root, (sx * 0.072, -0.152, 0.0), (sx * 0.02, -0.205, 0.004), 8)
        else:
            pts = _bezier(root, (0.0, -0.168, 0.014), (0.0, -0.196, 0.052), 8)
        radii = [0.016 * (1 - i / 8) ** 0.8 + 0.0025 for i in range(9)]
        objs.append(fin(sweep("HCl_Finger", pts, radii, "Steel", sides=10), angle=60))
        objs.append(fin(sphere("HCl_Knuckle", 0.019, root, "Iron", 14, 7), angle=80))
    objs.append(fin(revolve("HCl_Pin", [(0.0, -0.044), (0.011, -0.044), (0.011, 0.044), (0.0, 0.044)], "Steel", 10,
                            T((0.0, -0.1, 0.0)) @ Rx(90.0)), 0.001, 1, uv="cyl", axis='Z'))
    objs.append(band("HCl_Stripe", -0.058, 0.05, 0.014, "Shirt_Kit"))
    return objs, [socket(), shape_box("Hand", (0.0, -0.12, 0.0), (0.12, 0.16, 0.07))]


def build_Hand_Clamp(base="Iron"):
    """Тиски: железный корпус, две толстые губки на болтах с насечкой внутрь, винт поперёк с воротком снаружи
    (+X — внешняя сторона левой руки, правая — зеркало), полоска цвета игрока."""
    objs = ferrule("HCp_Cuff", -0.012, -0.05, 0.046)
    objs.append(rbox("HCp_Body", (0.108, 0.05, 0.072), "Base_" + base, (0.0, -0.074, 0.0), 0.014, 2))
    objs.append(rbox("HCp_Stripe", (0.112, 0.014, 0.076), "Shirt_Kit", (0.0, -0.064, 0.0), 0.005, 2))
    jaw = [(0.016, -0.09), (0.05, -0.09), (0.058, -0.104), (0.061, -0.125), (0.059, -0.15), (0.053, -0.172), (0.043, -0.19),
           (0.028, -0.2), (0.01, -0.2), (0.006, -0.194), (0.007, -0.186), (0.015, -0.181), (0.015, -0.1)]
    for sx in (-1, 1):
        objs.append(fin(extrude2d("HCp_Jaw", [(sx * x, y) for x, y in jaw], -0.028, 0.028, "Base_" + base), 0.005, 2, angle=40))
        for k in range(4):   # насечка: стальные ромбы на губке
            objs.append(fin(box("HCp_Tooth", (0.008, 0.008, 0.05), "Steel", xf=T((sx * 0.0155, -0.128 - 0.015 * k, 0.0)) @ Rz(45.0))))
        for sz in (1, -1):
            objs.append(fin(stud("HCp_Pivot", (sx * 0.034, -0.102, sz * 0.028), (0, 0, sz), "Steel", 0.011, 0.006, 6)))
    y_s = -0.116
    objs.append(fin(revolve("HCp_Screw", [(0.0, -0.066), (0.0065, -0.066), (0.0065, 0.076), (0.0, 0.076)], "Steel", 10,
                            T((0.0, y_s, 0.0)) @ Rz(-90.0)), uv="cyl", axis='X'))
    for x in (-0.008, 0.0, 0.008):   # резьба в зазоре между губками
        objs.append(fin(torus("HCp_Thread", (x, y_s, 0.0), 0.0068, 0.0022, "Steel", 'YZ', 10, 4), angle=80))
    objs.append(fin(stud("HCp_Nut", (-0.061, y_s, 0.0), (-1, 0, 0), "Steel", 0.011, 0.007, 6)))
    objs.append(fin(sphere("HCp_Boss", 0.009, (0.074, y_s, 0.0), "Iron", 12, 6), angle=80))
    objs.append(fin(revolve("HCp_Handle", [(0.0, -0.026), (0.0045, -0.026), (0.0045, 0.026), (0.0, 0.026)], "Steel", 8,
                            T((0.074, y_s, 0.0))), uv="cyl"))
    for sy in (1, -1):
        objs.append(fin(sphere("HCp_Knob", 0.008, (0.074, y_s + sy * 0.027, 0.0), "Brass", 12, 6), angle=80))
    return objs, [socket(), shape_box("Hand", (0.0, -0.124, 0.0), (0.13, 0.15, 0.06))]


def build_Hand_Paddle(base="Wood"):
    """Лопасть-весло (шлёпать): манжет, короткое древко с железным хомутом, широкая плоская лопасть с ребром,
    окованный край на латунных заклёпках, полоса цвета игрока поперёк."""
    objs = ferrule("HPd_Cuff", -0.012, -0.05, 0.046)
    objs.append(fin(revolve("HPd_Shaft", [(0.0, -0.044), (0.025, -0.044), (0.022, -0.06), (0.02, -0.08), (0.023, -0.098), (0.0, -0.1)],
                            "Base_" + base, 16), 0.002, 1, uv="cyl"))
    objs.append(band("HPd_Collar", -0.09, 0.027, 0.02, "Iron"))
    objs += ring_rivets("HPd_CollarRivet", -0.09, 0.027, 4, "Steel", 0.005, front_only=True)
    half = [(0.024, -0.09), (0.036, -0.096), (0.05, -0.103), (0.061, -0.113), (0.068, -0.128), (0.07, -0.15), (0.068, -0.175),
            (0.062, -0.196), (0.051, -0.213), (0.035, -0.226), (0.018, -0.234)]
    outline = half + [(0.0, -0.238)] + [(-x, y) for x, y in reversed(half)]
    objs.append(fin(extrude2d("HPd_Blade", outline, -0.012, 0.012, "Base_" + base), 0.007, 2, angle=40))
    for sz in (1, -1):   # ребро-хребет лопасти с обеих сторон
        rib = [(0.0, -0.1 - 0.013 * i, sz * 0.011) for i in range(6)]
        objs.append(fin(sweep("HPd_Rib", rib, [0.009 - 0.001 * i for i in range(6)], "Base_" + base, sides=8), angle=60))
    edge = [Vector(p + (0.0,)) for p in outline if p[1] < -0.195]
    dense = []
    for a, b in zip(edge, edge[1:]):
        dense += [a, (a + b) / 2]
    dense.append(edge[-1])
    objs.append(fin(sweep("HPd_Edge", dense, 0.0135, "Iron", sides=8), angle=60))
    for x, y in ((0.051, -0.213), (0.0, -0.238), (-0.051, -0.213)):
        objs.append(fin(stud("HPd_EdgeRivet", (x, y + 0.004, 0.0132), (0, 0, 1), "Brass", 0.0055, 0.0035, 6)))
    stripe = [(x * 0.006, -0.166) for x in range(-9, 10)] + [(x * 0.006, -0.182) for x in range(9, -10, -1)]
    for z0, z1 in ((0.0115, 0.0145), (-0.0145, -0.0115)):
        objs.append(fin(extrude2d("HPd_Stripe", stripe, z0, z1, "Shirt_Kit"), 0.001, 1))
    return objs, [socket(), shape_box("Hand", (0.0, -0.148, 0.0), (0.14, 0.2, 0.06))]


def build_Hand_Fist(base="Rust"):
    """Кулак-болванка: литой ржавый куб, четыре пальца-валика, большой палец поперёк сверху, железный кастет с заклёпками
    на костяшках, ремень цвета игрока на запястье."""
    objs = ferrule("HFs_Cuff", -0.012, -0.05, 0.046)
    objs.append(rbox("HFs_Palm", (0.114, 0.11, 0.086), "Base_" + base, (0.0, -0.105, -0.004), 0.02, 3))
    objs.append(rbox("HFs_Strap", (0.12, 0.018, 0.092), "Shirt_Kit", (0.0, -0.064, -0.004), 0.006, 2))
    xs = [(k - 1.5) * 0.0285 for k in range(4)]
    for x in xs:
        objs.append(rbox("HFs_Finger", (0.026, 0.074, 0.034), "Base_" + base, (x, -0.123, 0.04), 0.012, 2))
        objs.append(fin(_dome("HFs_Knuckle", 0.016, (x, -0.156, 0.006), "Base_" + base, 1.0, 12, 6), angle=70))
    thumb = [(0.058, -0.08, 0.01), (0.062, -0.088, 0.042), (0.042, -0.094, 0.064), (0.018, -0.096, 0.066)]
    objs.append(fin(sweep("HFs_Thumb", thumb, [0.019, 0.018, 0.016, 0.015], "Base_" + base, sides=12), angle=70))
    objs.append(fin(sphere("HFs_ThumbTip", 0.015, thumb[-1], "Base_" + base, 12, 6), angle=80))
    objs.append(rbox("HFs_Duster", (0.122, 0.02, 0.022), "Iron", (0.0, -0.152, 0.056), 0.006, 2))
    for x in xs:
        objs.append(fin(stud("HFs_Rivet", (x, -0.152, 0.067), (0, 0, 1), "Steel", 0.007, 0.005, 6)))
    return objs, [socket(), shape_box("Hand", (0.0, -0.111, 0.008), (0.124, 0.13, 0.1))]


def build_Foot_Boot(base="Wood"):
    """Ботинок: манжет, пухлый верх, резиновая подошва, железный носок-колпак с заклёпками, ремень цвета игрока (стопа к камере)."""
    objs = ferrule("FB_Cuff", -0.004, -0.036, 0.05)
    objs.append(rbox("FB_Upper", (0.11, 0.07, 0.2), "Base_" + base, (0.0, -0.045, 0.045), 0.03, 3))
    objs.append(rbox("FB_Sole", (0.12, 0.024, 0.26), "Rubber", (0.0, -0.078, 0.055), 0.01, 2))
    c, r, sy = Vector((0.0, -0.054, 0.13)), 0.06, 0.6   # колпак сплюснут: низ на подошве (−0.09), а не под ней
    objs.append(fin(_dome("FB_Toe", r, tuple(c), "Iron", sy, 20, 10), angle=70))
    for sx in (-1, 0, 1):
        n = Vector((sx * 0.45, 0.55, 0.7)).normalized()
        p = c + Vector((n.x * r, n.y * r * sy, n.z * r))
        objs.append(fin(stud("FB_ToeRivet", tuple(p), tuple(Vector((n.x, n.y / sy, n.z)).normalized()), "Steel", 0.006, 0.004, 6)))
    objs.append(rbox("FB_Strap", (0.118, 0.075, 0.03), "Shirt_Kit", (0.0, -0.042, 0.06), 0.01, 2))
    return objs, [socket(), shape_box("Foot", (0.0, -0.05, 0.05), (0.1, 0.08, 0.25))]


def build_Foot_Peg(base="WoodDark"):
    """Нога-колышек: сужающийся тёмный колышек с резиновой набойкой, поясок цвета игрока."""
    objs = ferrule("FP_Cuff", -0.004, -0.03, 0.048)
    objs.append(fin(revolve("FP_Peg", [(0.0, -0.02), (0.044, -0.02), (0.036, -0.05), (0.026, -0.068), (0.0, -0.07)], "Base_" + base, 18),
                    uv="cyl"))
    objs.append(band("FP_Stripe", -0.036, 0.0405, 0.01, "Shirt_Kit"))
    objs.append(fin(sphere("FP_Tip", 0.024, (0.0, -0.068, 0.0), "Rubber", 14, 7), angle=80))
    return objs, [socket(), shape_sphere("Foot", (0.0, -0.06, 0.0), 0.03)]


def build_Foot_Wheel(base="PaintRed"):
    """Колесо-самокат: манжет, железная вилка перед лодыжкой (кронштейн, коронка, две щёки), крашеный диск с резиновой шиной
    на стальной оси вдоль Z, кольцо цвета игрока; форма — шар: круг в плоскости боя, катится."""
    c = Vector((0.0, -0.048, 0.085))   # центр колеса: низ шины на −0.09, впереди шара лодыжки
    objs = ferrule("FW_Cuff", -0.004, -0.036, 0.048)
    objs.append(rbox("FW_Bracket", (0.026, 0.042, 0.034), "Iron", (0.0, -0.012, 0.048), 0.008, 2))
    objs.append(rbox("FW_Crown", (0.044, 0.02, 0.072), "Iron", (0.0, 0.011, c.z), 0.007, 2))
    cheek = [(-0.016, 0.014), (0.016, 0.014)] + [(0.013 * math.cos(math.pi * k / 8), c.y - 0.013 * math.sin(math.pi * k / 8))
                                               for k in range(9)]
    for zc in (c.z - 0.023, c.z + 0.023):
        objs.append(fin(extrude2d("FW_Cheek", cheek, zc - 0.004, zc + 0.004, "Iron"), 0.002, 1, angle=40))
    objs.append(fin(_zrev("FW_Axle", [(0.0, -0.036), (0.0055, -0.036), (0.0055, 0.036), (0.0, 0.036)], "Steel", c, 10),
                    uv="cyl", axis='Z'))
    for sz in (1, -1):
        objs.append(fin(stud("FW_Nut", (c.x, c.y, c.z + sz * 0.027), (0, 0, sz), "Steel", 0.009, 0.006, 6)))
    disc = [(0.0, 0.013), (0.01, 0.013), (0.013, 0.009), (0.025, 0.0075), (0.031, 0.011), (0.033, 0.006), (0.033, -0.006),
            (0.031, -0.011), (0.025, -0.0075), (0.013, -0.009), (0.01, -0.013), (0.0, -0.013)]
    objs.append(fin(_zrev("FW_Disc", disc, "Base_" + base, c, 28), 0.0, uv="cyl", axis='Z', angle=50))
    tyre = [(0.03, -0.012), (0.034, -0.015), (0.039, -0.014), (0.0415, -0.009), (0.042, 0.0), (0.0415, 0.009), (0.039, 0.014),
            (0.034, 0.015), (0.03, 0.012)]
    objs.append(fin(_zrev("FW_Tyre", tyre, "Rubber", c, 32, closed=True), uv="cyl", axis='Z', angle=60))
    objs.append(fin(torus("FW_Stripe", (c.x, c.y, c.z + 0.0085), 0.021, 0.0028, "Shirt_Kit", 'XY', 24, 5), angle=80))
    return objs, [socket(), shape_sphere("Foot", (0.0, c.y, 0.0), 0.042)]


def build_Foot_Spring(base="Pink"):
    """Пого-пружина: манжет, железная тарелка с кольцом цвета игрока, открытая стальная пружина шире шара лодыжки,
    со штоком, толстая набойка-бублик (Base_Pink = резина: MaterialDef rubber даёт отскок)."""
    objs = ferrule("FSp_Cuff", -0.004, -0.022, 0.046)
    objs.append(fin(revolve("FSp_Top", [(0.0, -0.018), (0.054, -0.018), (0.061, -0.022), (0.061, -0.027), (0.054, -0.031), (0.0, -0.031)],
                            "Iron", 24), 0.0, uv="cyl"))
    objs.append(band("FSp_Stripe", -0.0245, 0.0625, 0.007, "Shirt_Kit"))
    y_a, y_b, turns = -0.03, -0.064, 2.25
    n = int(turns * 20)
    coil = []
    for i in range(n + 1):
        t = i / n
        a = TAU * turns * t
        rr = 0.045 + 0.006 * math.sin(math.pi * t)
        coil.append((math.cos(a) * rr, y_a + (y_b - y_a) * t, math.sin(a) * rr))
    objs.append(fin(sweep("FSp_Coil", coil, 0.0055, "Steel", sides=7), angle=80))
    objs.append(fin(revolve("FSp_Rod", [(0.0, y_a), (0.012, y_a), (0.012, y_b), (0.0, y_b)], "Steel", 12), uv="cyl"))
    objs.append(fin(revolve("FSp_Cup", [(0.0, -0.06), (0.05, -0.06), (0.055, -0.063), (0.055, -0.066), (0.0, -0.066)], "Iron", 24),
                    0.0, uv="cyl"))
    objs.append(fin(revolve("FSp_Pad", [(0.0, -0.064), (0.05, -0.064), (0.059, -0.068), (0.064, -0.075), (0.064, -0.081), (0.06, -0.087),
                                        (0.051, -0.09), (0.0, -0.09)], "Base_" + base, 26), 0.0, uv="cyl"))
    return objs, [socket(), shape_cyl("Foot", (0.0, -0.061, 0.0), 0.062, 0.058)]


def build_Foot_Flipper(base="PaintGreen"):
    """Ласта: манжет, калоша, широкая плоская лопасть к камере с тремя «пальцами» и чёрными рёбрами, ремень цвета игрока."""
    objs = ferrule("FFl_Cuff", -0.004, -0.034, 0.05)
    objs.append(rbox("FFl_Shoe", (0.104, 0.054, 0.13), "Base_" + base, (0.0, -0.058, 0.03), 0.022, 3))
    objs.append(rbox("FFl_Strap", (0.11, 0.058, 0.026), "Shirt_Kit", (0.0, -0.056, 0.058), 0.008, 2))
    side = [(0.046, -0.02), (0.05, 0.05), (0.058, 0.1), (0.069, 0.15), (0.08, 0.195), (0.086, 0.225)]
    front = [(0.01 * k, 0.19 + 0.045 * abs(math.cos(math.pi * 0.01 * k / 0.09)) ** 0.8) for k in range(8, -9, -1)]
    rear = [(-0.03, -0.036), (0.0, -0.04), (0.03, -0.036)]
    outline = rear + side + front + [(-x, z) for x, z in reversed(side)]
    # контур в (x, z), толщина по y: Rx(90) переводит (u, v, t) → (u, −t, v); низ лопасти на −0.09
    objs.append(fin(extrude2d("FFl_Blade", outline, 0.078, 0.09, "Base_" + base, xf=Rx(90.0)), 0.004, 2, angle=40))
    for xt in (-0.066, 0.0, 0.066):
        rib = [(xt * (0.5 + 0.5 * i / 5), -0.0785, 0.09 + 0.024 * i) for i in range(6)]
        objs.append(fin(sweep("FFl_Rib", rib, [0.0068 - 0.0006 * i for i in range(6)], "Rubber", sides=8), angle=60))
    return objs, [socket(), shape_box("Foot", (0.0, -0.06, 0.03), (0.1, 0.06, 0.13)),
                  shape_box("Fin", (0.0, -0.084, 0.1), (0.17, 0.012, 0.27))]


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3): масса ≈ объём формы × плотность материала по умолчанию (Варежка 0.5 кг =
# wood_hand), энергия. body_mult здесь нет: у кисти и стопы своё тело, удар — Tuning.BODY_MULT по имени тела × материал узла
# (builder пишет в PartDef таблицу по name_prefix) × hit_mult — множитель удара ЭТОЙ формой (PartDef.hit_mult): клешня 1.15,
# тиски и кулак 1.1, острый колышек 1.15; тяжёлая кисть бьёт сильнее ещё и материалом (кулак — ржавчина, клешня — железо)
META = {
    "Hand_Mitten": {"kind": "hand", "title": "Варежка", "mass": 0.5, "energy": 2},
    "Hand_Claw": {"kind": "hand", "title": "Клешня", "mass": 0.9, "energy": 3, "hit_mult": 1.15},
    "Hand_Clamp": {"kind": "hand", "title": "Тиски", "mass": 1.1, "energy": 3, "hit_mult": 1.1},
    "Hand_Paddle": {"kind": "hand", "title": "Лопасть", "mass": 0.6, "energy": 2},
    "Hand_Fist": {"kind": "hand", "title": "Кулак", "mass": 1.5, "energy": 3, "hit_mult": 1.1},
    "Foot_Boot": {"kind": "foot", "title": "Ботинок", "mass": 1.0, "energy": 3},
    "Foot_Peg": {"kind": "foot", "title": "Колышек", "mass": 0.5, "energy": 2, "hit_mult": 1.15},
    "Foot_Wheel": {"kind": "foot", "title": "Колесо", "mass": 0.7, "energy": 3},
    "Foot_Spring": {"kind": "foot", "title": "Пого-пружина", "mass": 0.7, "energy": 4},
    "Foot_Flipper": {"kind": "foot", "title": "Ласта", "mass": 0.7, "energy": 3},
}
