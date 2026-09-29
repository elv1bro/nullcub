#!/usr/bin/env python3
"""THE SCRAP (биом 1 «Свалка»), механизмы листа 04 «Machines & Hazards» (docs/refs/biomes/01-scrap/sheet-04.png, LIST.md)
и лут крафта для арены «Свалка» v3: магнит на цепи (№079 Swinging Magnet / №070 Magnetic Crane), паровой клапан (№078),
пресс (№067 Crushing Press), мусорный желоб (№061 Garbage Chute), длинная цепь для подвесов и четыре материала-лута.
Состояния OFF / WARNING / ACTIVE / COOLDOWN (kit-02.png, «Interactive elements») показывают эмиссионные лампы: слоты
материалов Lamp (лампы-плафоны) и Coil (рабочая поверхность магнита) — в Godot поведение (scenes/props/scrap/machines/*.gd)
подменяет их своими материалами с цветом и яркостью состояния.

Стиль и сетка — как у модульного кита (tools/blender/scrap_kit.py): те же PBR-наборы Свалки из assets/textures/pbr
(rust_metal, rust_painted_red, scrap_wood, brass_worn; слоты RustIron / RustIronDark / RustRed / ScrapWood / ScrapWoodDark /
Brass), те же детали (узлы с гнездом, заклёпки, болты, цепи, фаски, латунная корона). Хелперы кита НЕ копируются: исходник
scrap_kit.py исполняется в отдельное пространство имён без последней строки `main()` (_load_kit) — правило одно на оба
скрипта. Если в scrap_kit.py после main() появится код, поправить _load_kit.

Запуск (headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_machines.py [-- Имя …]
        → godot/assets/models/scrap/machines/<Name>.glb  (Y вверх в Godot; бюджет треугольников — BUDGET, скрипт падает
                                                          при превышении); печатает таблицу треугольников и габаритов
Переменные окружения — как у scrap_kit.py (SCRAP_KIT_TEX, SCRAP_KIT_IMG, SCRAP_KIT_CACHE, SCRAP_FLAT).

Соглашения: метры; Blender Z вверх, X вбок, «лицо» в −Y (в Godot +Z, к камере); «за плоскостью боя» = Blender +Y
(Godot z < 0). Габариты ниже — в осях Godot: x, y (вверх), z (к камере).

Модели (assets/models/scrap/machines/<Name>.glb):
    Magnet_Head     электромагнит-«таблетка» Ø1.56 × 1.17: скоба-серьга на origin (точка подвеса к цепи), щёки-ярмо
                    с пальцем, корпус с красным поясом и заклёпками, радиальные рёбра крышки, кабель, три лампы Lamp на
                    поясе (лицом к камере), снизу — полюс и кольцо Coil (светится в ACTIVE); origin — верх серьги,
                    рабочая поверхность — y = −1.17
    Gantry_Rail     балка-рельс 9 м (двутавр) с тележкой, блоком и серьгой подвеса маятника магнита; концы — стойки вверх
                    из кадра; лампа Lamp на тележке; origin — точка подвеса (низ серьги), балка на y +0.55…+0.95
    Chain_Long      вертикальная цепь 2.0 м (16 звеньев, шаг 0.125 — модули стыкуются без шва); origin — верх, до y −2.0
    Steam_Vent      паровой клапан: патрубок Ø0.8 на полу (верх с решёткой y 0.38), подвод трубой из-за плоскости боя
                    (z −0.3…−1.35), стояк до y 2.4 с латунным вентилем и манометром, фонарь Lamp в клетке на кронштейне;
                    origin — центр основания патрубка на полу
    Press_Frame     станина пресса: две колонны 0.45 за плоскостью боя (x ±1.35, z −1.2), ригель, головная траверса
                    (x ±1.3, y 5.0…5.7, z −0.55…+0.5) с латунной короной, гидроцилиндр Ø0.6 (y 4.4…7.9), направляющие,
                    наковальня-плита на полу (2.5 × 0.12 × 1.24, полосы «осторожно»), фонари Lamp на колоннах и
                    маячок на траверсе, пульт с манометром; origin — центр основания (пол), ползун — отдельно
    Press_Ram       ползун: блок 2.0 × 0.68 × 1.2 с зубьями снизу (0.12), полосы «осторожно» на лице, латунная
                    корона, шток Ø0.26 до y 4.45 (всегда в цилиндре), ползушки к направляющим; origin — низ зубьев
    Garbage_Chute   мусорный желоб: клёпаная труба Ø1.24 сверху из-за кадра (вертикальный участок x −2.25, z −1.3 до
                    y +8.2 над раструбом, колено вниз-вправо) в раструб на плоскости боя, фланцы, красные пояса, хомут с
                    растяжкой назад, откидная заслонка, застрявший хлам, лампа Lamp; origin — центр раструба, раструб смотрит
                    вниз-вправо (ось (0.55, −0.83, 0))
    Loot_Nails      связка шести гвоздей с проволокой и красной биркой (0.42 × 0.16)
    Loot_Plate      клёпаная железная пластина лицом к камере с загнутым углом (0.44 × 0.32 × 0.04)
    Loot_Chain      обрывок цепи из трёх звеньев (0.46)
    Loot_Handle     рукоять: брусок клёна с железной обоймой и красной обмоткой (0.56 × 0.07)
    Лут лежит в плоскости XY (оси x/y вращения у тел заперты) — лицо всегда к камере.
"""
import math
import os
import sys
import types
import zlib

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402


def _load_kit():
    """Хелперы и материалы кита: исходник scrap_kit.py без завершающего вызова main()."""
    path = os.path.join(HERE, "scrap_kit.py")
    src = open(path, encoding="utf-8").read()
    head, sep, tail = src.rpartition("\nmain()")
    if not sep or tail.strip():
        raise RuntimeError("scrap_kit.py: ожидался последний оператор main() — поправь _load_kit")
    mod = types.ModuleType("scrap_kit_lib")
    mod.__file__ = path
    exec(compile(head, path, "exec"), mod.__dict__)
    return mod


K = _load_kit()
Kit, g_box, g_prism, g_lathe, g_cyl, g_torus, g_tube = K.Kit, K.g_box, K.g_prism, K.g_lathe, K.g_cyl, K.g_torus, K.g_tube
rivet, bolt, chain, node, crown_plate, flat_bar, align_z = K.rivet, K.bolt, K.chain, K.node, K.crown_plate, K.flat_bar, K.align_z
RNG = K.RNG
TAU = 2.0 * math.pi
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "scrap", "machines")
BUDGET = {"Chain_Long": 1200, "Gantry_Rail": 3000, "Magnet_Head": 4000, "Steam_Vent": 4000, "Press_Frame": 5000,
          "Press_Ram": 3000, "Garbage_Chute": 5000, "Loot_Nails": 800, "Loot_Plate": 600, "Loot_Chain": 600,
          "Loot_Handle": 600}


# ----------------------------------------------------------------------------------------------------------------------
# эмиссионные слоты состояний: в glb — тёплое свечение по умолчанию (как OFF-лампа), в Godot подменяются поведением
# ----------------------------------------------------------------------------------------------------------------------
def _emissive(name, base, emit, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = emit
    bsdf.inputs["Emission Strength"].default_value = strength
    m.use_backface_culling = True
    return m


def _state_materials():
    """Слоты Lamp / Coil — после reset_scene (он чистит bpy.data), до первой модели."""
    K._MATS["Lamp"] = _emissive("Lamp", (0.85, 0.55, 0.30, 1.0), (1.0, 0.55, 0.22, 1.0), 1.0)
    K._MATS["Coil"] = _emissive("Coil", (0.30, 0.22, 0.16, 1.0), (1.0, 0.45, 0.18, 1.0), 0.3)


FRONT = Vector((0, -1, 0))


def lamp_dome(Kt, loc, n=FRONT, r=0.075, cage=True, bezel_mat="RustIron"):
    """Плафон-лампа: ободок, стеклянный купол Lamp лицом по n, клетка из двух дуг."""
    rot = align_z(n)
    Kt.add(g_lathe([(r + 0.025, 0.0), (r + 0.025, 0.025), (r, 0.03), (r, 0.0)], segs=10), bezel_mat, loc=loc, rot=rot)
    Kt.add(g_lathe([(r * 0.96, 0.025), (r * 0.8, 0.06), (r * 0.45, 0.085), (0.0, 0.092)], segs=10), "Lamp", loc=loc, rot=rot)
    if cage:
        for a in (0.0, math.pi / 2):
            pts = [Vector((r * 1.02 * math.cos(t), 0.0, 0.02 + r * 1.05 * math.sin(t))) for t in
                   [math.pi * k / 6 for k in range(7)]]
            m = rot @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(math.pi / 2, 4, 'X')
            Kt.add(g_tube(pts, [0.008] * len(pts), sides=4, cap0=False, tip=False), "RustIronDark", loc=loc, rot=m, uv=False)


def band(Kt, r, z0, z1, mat="RustRed", segs=24, a0=None, a1=None):
    """Пояс-обечайка вокруг Z (открытый цилиндр) радиуса r от z0 до z1."""
    Kt.add(g_lathe([(r, z0), (r + 0.012, z0 + 0.01), (r + 0.012, z1 - 0.01), (r, z1)], segs=segs), mat)


def ring_rivets(Kt, r, z, a_from, a_to, n, rr=0.02):
    """Ряд заклёпок по окружности радиуса r на высоте z, углы в градусах (−90 — лицом к камере)."""
    for i in range(n):
        a = math.radians(a_from + (a_to - a_from) * i / max(1, n - 1))
        nrm = Vector((math.cos(a), math.sin(a), 0.0))
        rivet(Kt, Vector((r * math.cos(a), r * math.sin(a), z)), nrm, r=rr)


# ----------------------------------------------------------------------------------------------------------------------
# №079 / №070 магнит на цепи
# ----------------------------------------------------------------------------------------------------------------------
def magnet_head(name):
    Kt = Kit(name)
    # серьга подвеса: кольцо в плоскости XZ (стыкуется со звеном цепи, повёрнутым ребром), палец через щёки
    Kt.add(g_torus(0.07, 0.022, 10, 4), "RustIron", loc=(0, 0, -0.07), rot=(math.pi / 2, 0, 0))
    Kt.add(g_box(0.2, 0.36, 0.09, bevel=0.012), "RustIron", loc=(0, 0, -0.17))
    for y in (-0.15, 0.15):
        Kt.add(g_prism([(-0.14, -0.11), (0.14, -0.11), (0.52, -0.64), (-0.52, -0.64)], 0.05, bevel=0.01),
               "RustIronDark", loc=(0, y, 0), along='Z')
    pin = g_cyl(0.045, 0.44, segs=8)
    Kt.add(pin, "RustIron", loc=(0, 0, -0.17), rot=(0, 0, math.pi / 2))
    for y in (-0.22, 0.22):
        Kt.add(g_lathe([(0.07, 0.0), (0.07, 0.02), (0.0, 0.03)], segs=6), "RustIron", loc=(0, y, -0.17),
               rot=(math.pi / 2 if y < 0 else -math.pi / 2, 0, 0))
    for x, z in ((-0.26, -0.36), (0.26, -0.36), (-0.4, -0.55), (0.4, -0.55), (0.0, -0.5)):
        rivet(Kt, (x, -0.176, z), r=0.022)
    crown_plate(Kt, 0.0, -0.46, w=0.2, y=-0.19, t=0.02)
    # корпус: крышка с фаской, обечайка, нижний бортик
    prof = [(0.0, -0.62), (0.46, -0.62), (0.68, -0.66), (0.78, -0.72), (0.78, -1.06), (0.74, -1.10), (0.70, -1.12),
            (0.66, -1.12)]
    Kt.add(g_lathe(prof, segs=28), "RustIron")
    band(Kt, 0.782, -0.80, -0.96, "RustRed", segs=28)
    ring_rivets(Kt, 0.80, -0.775, -160, -20, 9, rr=0.018)
    ring_rivets(Kt, 0.80, -0.985, -160, -20, 9, rr=0.018)
    # радиальные рёбра крышки
    for i in range(8):
        a = TAU * i / 8 + math.pi / 8
        Kt.add(g_box(0.44, 0.05, 0.08, bevel=0.008), "RustIronDark",
               loc=(0.46 * math.cos(a), 0.46 * math.sin(a), -0.64), rot=(0, math.radians(-8), a), along='X')
    # низ: рабочее кольцо Coil (светится), полюс, разделители
    Kt.add(g_lathe([(0.66, -1.12), (0.64, -1.16), (0.30, -1.16), (0.28, -1.12)], segs=28), "Coil")
    Kt.add(g_lathe([(0.28, -1.12), (0.26, -1.17), (0.0, -1.17)], segs=16), "RustIronDark")
    for i in range(6):
        a = TAU * i / 6
        Kt.add(g_box(0.36, 0.04, 0.03), "RustIronDark", loc=(0.47 * math.cos(a), 0.47 * math.sin(a), -1.165),
               rot=(0, 0, a), along='X', uv=True)
    # лампы на поясе лицом к камере и кабель от ярма к крышке
    for ang in (-125, -90, -55):
        a = math.radians(ang)
        n = Vector((math.cos(a), math.sin(a), 0.0))
        lamp_dome(Kt, n * 0.79 + Vector((0, 0, -0.88)), n, r=0.055, cage=False)
    cable = [Vector((0.30, -0.05, -0.30)), Vector((0.46, -0.12, -0.42)), Vector((0.56, -0.18, -0.58)), Vector((0.58, -0.2, -0.66))]
    Kt.add(g_tube(cable, [0.028] * 4, sides=6, cap0=True, tip=False), "RustIronDark", uv=False)
    Kt.add(g_box(0.12, 0.1, 0.07, bevel=0.01), "RustIron", loc=(0.58, -0.2, -0.66))
    return Kt.finish()


def gantry_rail(name, L=9.0):
    Kt = Kit(name)
    zb, h = 0.55, 0.40
    # двутавр: полки и стенка
    Kt.add(g_box(L, 0.36, 0.05, bevel=0.01), "RustIron", loc=(0, 0, zb + 0.025), along='X')
    Kt.add(g_box(L, 0.36, 0.05, bevel=0.01), "RustIron", loc=(0, 0, zb + h - 0.025), along='X')
    Kt.add(g_box(L, 0.05, h - 0.1, inset=(), drop=()), "RustIronDark", loc=(0, 0, zb + h / 2), along='X')
    for i in range(int(L / 0.75)):
        x = -L / 2 + 0.375 + 0.75 * i
        Kt.add(g_box(0.04, 0.3, h - 0.1), "RustIronDark", loc=(x, 0, zb + h / 2))
        rivet(Kt, (x, -0.18, zb + 0.05), (0, -1, 0), r=0.016)
    # концевые стойки вверх из кадра
    for sg in (-1, 1):
        x = sg * (L / 2 - 0.2)
        Kt.add(g_box(0.34, 0.34, 3.0, bevel=0.012, inset=('-Y',), border=0.05, depth=0.015), "RustIronDark",
               loc=(x, 0.0, zb + h + 1.5))
        node(Kt, x, 0.0, z_top=zb + h + 0.3, s=0.44, h=0.5)
        Kt.add(g_prism([(0, 0), (-sg * 0.6, 0), (0, 0.6)], 0.04, bevel=0.006), "RustIron", loc=(x - sg * 0.17, -0.1, zb + h))
    # тележка: корпус, 4 колеса на нижней полке, блок и серьга
    Kt.add(g_box(0.8, 0.5, 0.32, bevel=0.02, inset=('-Y',), border=0.05, depth=0.015), "RustRed", loc=(0, 0, zb - 0.02))
    for x in (-0.3, 0.3):
        for y in (-0.22, 0.22):
            w = g_cyl(0.09, 0.05, segs=10)
            Kt.add(w, "RustIronDark", loc=(x, y, zb + 0.14), rot=(0, 0, math.pi / 2))
        rivet(Kt, (x, -0.25, zb + 0.05), r=0.02)
    Kt.add(g_box(0.3, 0.3, 0.26, bevel=0.015), "RustIron", loc=(0, 0, zb - 0.31))
    Kt.add(g_prism([(-0.07, 0.0), (0.07, 0.0), (0.05, -0.12), (-0.05, -0.12)], 0.06, bevel=0.008), "RustIron",
           loc=(0, 0, zb - 0.44))
    Kt.add(g_torus(0.06, 0.018, 10, 4), "RustIron", loc=(0, 0, 0.07), rot=(0, math.pi / 2, 0))
    lamp_dome(Kt, Vector((0.26, -0.25, zb - 0.02)), FRONT, r=0.05, cage=True)
    crown_plate(Kt, -0.2, zb - 0.12, w=0.18, y=-0.255, t=0.02)
    return Kt.finish()


def chain_long(name, L=2.0, n=16):
    Kt = Kit(name)
    chain(Kt, [(0, 0, 0), (0, 0, -L)], R=0.058, r=0.017, segs=8, ring=4, pitch=L / n)
    return Kt.finish()


# ----------------------------------------------------------------------------------------------------------------------
# №078 паровой клапан
# ----------------------------------------------------------------------------------------------------------------------
def steam_vent(name):
    Kt = Kit(name)
    prof = [(0.46, 0.0), (0.46, 0.06), (0.37, 0.07), (0.35, 0.09), (0.35, 0.29), (0.41, 0.30), (0.41, 0.38), (0.30, 0.38),
            (0.29, 0.33)]
    Kt.add(g_lathe(prof, segs=20), "RustIron")
    Kt.add(g_lathe([(0.29, 0.33), (0.0, 0.33)], segs=12), "RustIronDark")
    band(Kt, 0.352, 0.13, 0.22, "RustRed", segs=20)
    ring_rivets(Kt, 0.47, 0.065, -165, -15, 7, rr=0.022)
    ring_rivets(Kt, 0.42, 0.34, -160, -20, 6, rr=0.018)
    # решётка на выходе
    for x in (-0.14, 0.0, 0.14):
        Kt.add(g_box(0.035, 0.58 - abs(x) * 1.2, 0.04), "RustIronDark", loc=(x, 0, 0.36))
    Kt.add(g_box(0.58, 0.035, 0.04), "RustIronDark", loc=(0, 0, 0.365))
    # подвод из-за плоскости боя: колено назад и вверх в стояк
    feed = [Vector((0, 0.25, 0.2)), Vector((0, 0.7, 0.2)), Vector((0, 1.0, 0.26)), Vector((0, 1.18, 0.42)),
            Vector((0, 1.25, 0.7)), Vector((0, 1.25, 2.4))]
    Kt.add(g_tube(feed, [0.17] * len(feed), sides=12, cap0=False, tip=False), "RustIron")
    for z in (0.95, 1.9):
        Kt.add(g_lathe([(0.17, -0.035), (0.22, -0.035), (0.22, 0.035), (0.17, 0.035)], segs=12), "RustIronDark", loc=(0, 1.25, z))
    Kt.add(g_lathe([(0.2, 0.0), (0.2, 0.05), (0.0, 0.06)], segs=12), "RustIronDark", loc=(0, 1.25, 2.4))
    # латунный вентиль на стояке (лицом к камере)
    stem = g_cyl(0.03, 0.25, segs=6)
    Kt.add(stem, "Brass", loc=(0, 1.0, 1.35), rot=(0, 0, math.pi / 2))
    wheel_c = Vector((0, 0.86, 1.35))
    Kt.add(g_torus(0.19, 0.024, 16, 4), "Brass", loc=wheel_c, rot=(math.pi / 2, 0, 0))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        Kt.add(g_box(0.19, 0.022, 0.022), "Brass", loc=wheel_c + Vector((0.095 * math.cos(a), 0, 0.095 * math.sin(a))),
               rot=(0, -a, 0), along='X')
    Kt.add(g_lathe([(0.045, 0.0), (0.045, 0.04), (0.0, 0.05)], segs=8), "Brass", loc=wheel_c, rot=(math.pi / 2, 0, 0))
    # манометр
    gauge = Vector((0.18, 1.08, 1.95))
    Kt.add(g_cyl(0.02, 0.1, segs=6), "Brass", loc=gauge + Vector((-0.07, 0.04, 0)))
    Kt.add(g_lathe([(0.11, 0.0), (0.11, 0.05), (0.095, 0.055), (0.0, 0.055)], segs=14), "Brass", loc=gauge,
           rot=(math.pi / 2, 0, 0))
    Kt.add(g_box(0.012, 0.008, 0.08), "RustIronDark", loc=gauge + Vector((0.02, -0.058, 0.02)), rot=(0, 0.6, 0))
    # фонарь на кронштейне
    Kt.add(g_box(0.5, 0.06, 0.06, bevel=0.008), "RustIronDark", loc=(-0.25, 1.1, 2.1), along='X')
    Kt.add(g_box(0.18, 0.14, 0.2, bevel=0.012), "RustIron", loc=(-0.5, 1.02, 2.1))
    lamp_dome(Kt, Vector((-0.5, 0.95, 2.1)), FRONT, r=0.07, cage=True)
    # красная бирка
    Kt.add(g_box(0.16, 0.02, 0.1, bevel=0.008), "RustRed", loc=(0.22, 0.99, 0.95), rot=(0, 0.1, 0))
    return Kt.finish()


# ----------------------------------------------------------------------------------------------------------------------
# №067 пресс: станина и ползун
# ----------------------------------------------------------------------------------------------------------------------
COL_X, COL_Y, COL_W = 1.35, 1.2, 0.45
CROWN_Z0, CROWN_Z1 = 5.0, 5.7
CYL_Z0, CYL_Z1 = 4.4, 7.9


def hazard_stripes(Kt, x0, x1, z0, z1, y, n=6, mats=("Brass", "RustIronDark"), t=0.012):
    """Полосы «осторожно» на плоскости y (лицом −Y): наклонные параллелограммы попеременно латунь / тёмное железо."""
    w = (x1 - x0) / n
    sk = (z1 - z0) * 0.6
    for i in range(n):
        xa = x0 + i * w
        pts = [(max(x0, xa), z0), (min(x1, xa + w), z0), (min(x1, xa + w + sk), z1), (min(x1, max(x0, xa + sk)), z1)]
        if pts[3][0] >= pts[2][0] - 1e-4:
            pts = [(max(x0, xa), z0), (min(x1, xa + w), z0), (min(x1, xa + w), z1), (max(x0, xa), z1)]
        Kt.add(g_prism(pts, t), mats[i % 2], loc=(0, y, 0), along='Z')


def press_frame(name):
    Kt = Kit(name)
    for sg in (-1, 1):
        x = sg * COL_X
        Kt.add(g_box(COL_W, COL_W, CROWN_Z1 - 0.3, bevel=0.015, inset=('-Y',), border=0.07, depth=0.02), "RustIronDark",
               loc=(x, COL_Y, (CROWN_Z1 - 0.3) / 2 + 0.3))
        node(Kt, x, COL_Y, z_top=0.34, s=COL_W + 0.14, h=0.3)
        Kt.add(g_box(0.7, 0.7, 0.06, bevel=0.012), "RustIron", loc=(x, COL_Y, 0.03))
        z = 0.6
        while z < CROWN_Z0 - 0.3:
            rivet(Kt, (x - 0.14, COL_Y - COL_W / 2, z), r=0.02)
            rivet(Kt, (x + 0.14, COL_Y - COL_W / 2, z), r=0.02)
            z += 0.55
        # направляющая ползуна на внутренней грани (швеллер к плоскости боя)
        Kt.add(g_box(0.12, 0.5, CROWN_Z0 - 0.5, bevel=0.01), "RustIron", loc=(sg * (COL_X - 0.24), COL_Y - 0.42, CROWN_Z0 / 2 + 0.2))
        # фонарь на лице колонны
        Kt.add(g_box(0.24, 0.12, 0.3, bevel=0.012), "RustIron", loc=(x, COL_Y - COL_W / 2 - 0.05, 3.7))
        lamp_dome(Kt, Vector((x, COL_Y - COL_W / 2 - 0.11, 3.7)), FRONT, r=0.085, cage=True)
    # ригель за плоскостью и траверса к плоскости боя
    Kt.add(g_box(2 * COL_X + COL_W + 0.2, COL_W + 0.1, 0.55, bevel=0.015), "RustIron", loc=(0, COL_Y, CROWN_Z1 - 0.275))
    Kt.add(g_box(2.6, 1.1, CROWN_Z1 - CROWN_Z0, bevel=0.02, inset=('-Y',), border=0.08, depth=0.025), "RustIron",
           loc=(0, 0.0, (CROWN_Z0 + CROWN_Z1) / 2))
    Kt.add(g_box(2.6, COL_Y - 0.55, 0.3, drop=('-Z',)), "RustIronDark", loc=(0, (COL_Y + 0.55) / 2, CROWN_Z1 - 0.15))
    for x in (-1.1, -0.55, 0.55, 1.1):
        rivet(Kt, (x, -0.55, CROWN_Z1 - 0.07), r=0.022)
        rivet(Kt, (x, -0.55, CROWN_Z0 + 0.07), r=0.022)
    crown_plate(Kt, 0.0, CROWN_Z0 + 0.12, w=0.42, y=-0.57, t=0.03)
    hazard_stripes(Kt, -1.25, -0.4, CROWN_Z0 + 0.1, CROWN_Z1 - 0.1, -0.565, n=4)
    hazard_stripes(Kt, 0.4, 1.25, CROWN_Z0 + 0.1, CROWN_Z1 - 0.1, -0.565, n=4)
    # гидроцилиндр через траверсу, крышки и шпильки
    Kt.add(g_lathe([(0.0, CYL_Z0), (0.26, CYL_Z0), (0.3, CYL_Z0 + 0.04), (0.3, CYL_Z1 - 0.04), (0.26, CYL_Z1), (0.0, CYL_Z1)],
                   segs=20), "RustIron")
    for zz in (CYL_Z0 + 0.12, CROWN_Z1 + 0.2, CYL_Z1 - 0.15):
        Kt.add(g_lathe([(0.34, -0.05), (0.34, 0.05)], segs=20), "RustIronDark", loc=(0, 0, zz))
        ring_rivets(Kt, 0.345, zz, -150, -30, 5, rr=0.017)
    band(Kt, 0.305, CROWN_Z1 + 0.6, CROWN_Z1 + 1.1, "RustRed", segs=20)
    for sg in (-1, 1):
        Kt.add(g_cyl(0.028, CYL_Z1 - CROWN_Z1 + 0.1, segs=6), "RustIronDark", loc=(sg * 0.38, -0.05, (CYL_Z1 + CROWN_Z1) / 2),
               rot=(0, math.pi / 2, 0))
    # маячок на траверсе и шланг к пульту
    Kt.add(g_box(0.3, 0.3, 0.1, bevel=0.012), "RustIron", loc=(0.9, -0.2, CROWN_Z1 + 0.05))
    lamp_dome(Kt, Vector((0.9, -0.2, CROWN_Z1 + 0.1)), Vector((0, 0, 1)), r=0.1, cage=True)
    hose = [Vector((0.3, 0.1, CYL_Z0 + 0.3)), Vector((0.7, 0.3, CYL_Z0 + 0.1)), Vector((1.05, 0.7, 3.6)),
            Vector((1.2, 0.9, 2.6)), Vector((1.25, 0.95, 2.2))]
    Kt.add(g_tube(hose, [0.045] * len(hose), sides=6, cap0=True, tip=False), "RustIronDark", uv=False)
    Kt.add(g_box(0.5, 0.25, 0.6, bevel=0.015, inset=('-Y',), border=0.04, depth=0.012), "RustRed", loc=(1.9, 1.05, 1.9))
    Kt.add(g_lathe([(0.09, 0.0), (0.09, 0.03), (0.0, 0.035)], segs=12), "Brass", loc=(1.9, 0.92, 2.02), rot=(math.pi / 2, 0, 0))
    for dx in (-0.12, 0.0, 0.12):
        Kt.add(g_box(0.05, 0.04, 0.05, bevel=0.008), "Brass", loc=(1.9 + dx, 0.91, 1.75))
    # наковальня на полу: плита, полосы, болты
    Kt.add(g_box(2.5, 1.24, 0.12, bevel=0.02), "RustIronDark", loc=(0, 0, 0.06))
    for i in range(7):
        x0 = -1.2 + i * 0.36
        pts = [(x0, -0.6), (x0 + 0.18, -0.6), (x0 + 0.34, 0.6), (x0 + 0.16, 0.6)]
        g = g_prism([(p[0], p[1]) for p in pts], 0.012)
        g_rot = Matrix.Rotation(math.pi / 2, 4, 'X')
        Kt.add(g, "Brass", loc=(0, 0, 0.124), rot=g_rot, along='X')
    for x in (-1.12, 1.12):
        for y in (-0.5, 0.5):
            bolt(Kt, (x, y, 0.12), (0, 0, 1), s=0.04, h=0.02)
    return Kt.finish()


def press_ram(name):
    Kt = Kit(name)
    z0, z1 = 0.12, 0.80
    Kt.add(g_box(2.0, 1.2, z1 - z0, bevel=0.025, inset=('-Y',), border=0.07, depth=0.02), "RustIron", loc=(0, 0, (z0 + z1) / 2))
    hazard_stripes(Kt, -0.9, 0.9, z0 + 0.1, z0 + 0.3, -0.585, n=8)
    crown_plate(Kt, 0.0, z0 + 0.34, w=0.26, y=-0.59, t=0.025)
    for x in (-0.85, -0.45, 0.45, 0.85):
        rivet(Kt, (x, -0.6, z1 - 0.07), r=0.024)
    # зубья снизу
    n = 8
    for i in range(n):
        x = -0.9 + 1.8 * (i + 0.5) / n
        Kt.add(g_prism([(x - 0.1, z0), (x + 0.1, z0), (x, 0.0)], 1.1, bevel=0.0), "RustIronDark", loc=(0, 0, 0))
    # шток и манжета, ползушки к направляющим
    Kt.add(g_lathe([(0.24, z1), (0.24, z1 + 0.12), (0.13, z1 + 0.16), (0.13, 4.45), (0.0, 4.45)], segs=14), "RustIron")
    Kt.add(g_lathe([(0.18, z1 + 0.35), (0.18, z1 + 0.45)], segs=14), "RustIronDark")
    for sg in (-1, 1):
        Kt.add(g_box(0.22, 0.5, 0.5, bevel=0.012), "RustIronDark", loc=(sg * (COL_X - 0.26), 0.65, (z0 + z1) / 2))
    return Kt.finish()


# ----------------------------------------------------------------------------------------------------------------------
# №061 мусорный желоб
# ----------------------------------------------------------------------------------------------------------------------
def garbage_chute(name):
    Kt = Kit(name)
    R = 0.62
    path = [Vector((0, 0, 0)), Vector((-0.45, 0.12, 0.68)), Vector((-1.2, 0.5, 1.5)), Vector((-1.9, 0.95, 2.6)),
            Vector((-2.2, 1.2, 4.2)), Vector((-2.25, 1.3, 6.2)), Vector((-2.25, 1.3, 8.2))]
    # плотная ломаная по сплайну Катмулла–Рома, чтобы изгиб был гладким
    pts = []
    for i in range(len(path) - 1):
        p0, p1, p2, p3 = path[max(0, i - 1)], path[i], path[i + 1], path[min(len(path) - 1, i + 2)]
        for k in range(4):
            t = k / 4
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    pts.append(path[-1])
    Kt.add(g_tube(pts, [R] * len(pts), sides=18, cap0=False, tip=False), "RustIron")
    # внутренность раструба: тёмная обечайка и «дно» в глубине
    inner = pts[:5]
    g = g_tube(inner, [R - 0.05] * len(inner), sides=18, cap0=False, tip=False)
    import bmesh as _bm
    _bm.ops.reverse_faces(g, faces=list(g.faces))
    Kt.add(g, "RustIronDark", uv=True)
    d_in = (pts[4] - pts[3]).normalized()
    Kt.add(g_lathe([(0.0, -0.02), (R - 0.04, -0.02), (R - 0.04, 0.02), (0.0, 0.02)], segs=18), "RustIronDark", loc=pts[4],
           rot=align_z(d_in))
    # раструб: утолщённый край и заслонка на петлях сверху
    d0 = (pts[1] - pts[0]).normalized()
    Kt.add(g_torus(R + 0.02, 0.06, 20, 6), "RustIronDark", loc=pts[0] + d0 * 0.03, rot=align_z(d0))
    hinge = pts[0] + Vector((-0.55, -0.05, 0.42))
    Kt.add(g_cyl(0.04, 0.9, segs=6), "RustIron", loc=hinge + Vector((0, -0.2, 0)), rot=(0, 0, math.pi / 2))
    flap = g_box(0.05, 1.0, 0.9, bevel=0.01, inset=('-X',), border=0.06, depth=0.01)
    Kt.add(flap, "RustRed", loc=hinge + Vector((0.2, -0.2, -0.38)), rot=(0, math.radians(-28), 0))
    for dz in (-0.2, -0.6):
        rivet(Kt, hinge + Vector((0.2 + dz * math.sin(math.radians(-28)) * -1, -0.72, -0.38 + dz)), r=0.022)
    # фланцы и пояса вдоль трубы
    for i in (4, 10, 16, 21):
        c = pts[i]
        d = (pts[i + 1] - pts[i - 1]).normalized()
        Kt.add(g_lathe([(R + 0.06, -0.06), (R + 0.06, 0.06)], segs=18), "RustIronDark", loc=c, rot=align_z(d))
        rot = align_z(d)
        for k in range(8):
            a = -math.pi / 2 + (k - 3.5) * 0.3
            local = Vector((math.cos(a), math.sin(a), 0.0))
            n = (rot.to_3x3() @ local).normalized()
            if n.y > 0.2:
                continue
            rivet(Kt, c + n * (R + 0.065), n, r=0.022)
    for i in (7, 13, 19):
        c = pts[i]
        d = (pts[i + 1] - pts[i - 1]).normalized()
        Kt.add(g_lathe([(R + 0.015, -0.12), (R + 0.03, -0.1), (R + 0.03, 0.1), (R + 0.015, 0.12)], segs=18), "RustRed",
               loc=c, rot=align_z(d))
    # хомут с растяжкой назад (за плоскость боя) на вертикальном участке
    c = pts[17]
    Kt.add(g_lathe([(R + 0.03, -0.1), (R + 0.05, -0.08), (R + 0.05, 0.08), (R + 0.03, 0.1)], segs=18), "RustIronDark", loc=c)
    Kt.add(g_box(0.14, 1.4, 0.14, bevel=0.01), "RustIronDark", loc=c + Vector((0, R + 0.7, 0)))
    # застрявший хлам в раструбе
    for k in range(5):
        p = pts[0] + d0 * (0.15 + 0.12 * k) + Vector((RNG.uniform(-0.3, 0.3), RNG.uniform(-0.2, 0.25), RNG.uniform(-0.3, 0.1)))
        Kt.add(g_box(RNG.uniform(0.12, 0.3), RNG.uniform(0.05, 0.12), RNG.uniform(0.08, 0.22), bevel=0.008),
               "RustIronDark" if k % 2 else "ScrapWoodDark", loc=p, rot=(RNG.uniform(-1, 1), RNG.uniform(-1, 1), RNG.uniform(-1, 1)))
    # лампа на трубе у раструба
    lamp_at = pts[3] + Vector((0.25, -0.62, 0.15))
    Kt.add(g_box(0.2, 0.12, 0.2, bevel=0.012), "RustIron", loc=lamp_at + Vector((0, 0.04, 0)))
    lamp_dome(Kt, lamp_at + Vector((0, -0.02, 0)), FRONT, r=0.075, cage=True)
    return Kt.finish()


# ----------------------------------------------------------------------------------------------------------------------
# лут крафта (материалы) — плоские силуэты в плоскости XZ (лицом к камере)
# ----------------------------------------------------------------------------------------------------------------------
def loot_nails(name):
    Kt = Kit(name)
    for i in range(6):
        z = -0.05 + 0.02 * i + RNG.uniform(-0.006, 0.006)
        y = 0.02 * ((i % 3) - 1)
        x_off = RNG.uniform(-0.02, 0.02)
        Kt.add(g_cyl(0.011, 0.36, segs=6), "RustIron", loc=(x_off, y, z), rot=(0, 0, RNG.uniform(-0.05, 0.05)))
        Kt.add(g_lathe([(0.0, 0.0), (0.024, 0.0), (0.024, 0.008), (0.0, 0.01)], segs=6), "RustIron",
               loc=(x_off - 0.18, y, z), rot=(0, -math.pi / 2, 0))
        Kt.add(g_lathe([(0.011, 0.0), (0.0, 0.03)], segs=6), "RustIron", loc=(x_off + 0.18, y, z), rot=(0, math.pi / 2, 0))
    for x in (-0.07, 0.07):
        Kt.add(g_torus(0.055, 0.007, 10, 3, stretch=1.0), "RustIronDark", loc=(x, 0, 0.0), rot=(0, math.pi / 2, 0))
    Kt.add(g_box(0.08, 0.012, 0.06, bevel=0.005), "RustRed", loc=(0.02, -0.06, -0.075), rot=(0, 0.2, 0))
    return Kt.finish()


def loot_plate(name):
    Kt = Kit(name)
    pts = [(-0.22, -0.16), (0.22, -0.16), (0.22, 0.1), (0.16, 0.16), (-0.22, 0.16)]
    Kt.add(g_prism(pts, 0.04, bevel=0.006), "RustIron", along='Z')
    Kt.add(g_prism([(0.22, 0.1), (0.16, 0.16), (0.2, 0.19)], 0.03), "RustIronDark", loc=(0, -0.01, 0))
    for x, z in ((-0.17, -0.11), (0.17, -0.11), (-0.17, 0.11), (0.1, 0.11), (0.0, 0.0)):
        rivet(Kt, (x, -0.02, z), r=0.022, h=0.014)
    Kt.add(g_box(0.3, 0.006, 0.03), "RustRed", loc=(-0.02, -0.022, -0.05))
    return Kt.finish()


def loot_chain(name):
    Kt = Kit(name)
    chain(Kt, [(-0.2, 0, 0), (0.2, 0, 0)], R=0.058, r=0.018, segs=10, ring=4)
    Kt.add(g_box(0.07, 0.012, 0.05, bevel=0.004), "RustRed", loc=(0.0, -0.035, -0.06))
    return Kt.finish()


def loot_handle(name):
    Kt = Kit(name)
    Kt.add(g_box(0.5, 0.06, 0.07, bevel=0.012), "ScrapWood", loc=(0.03, 0, 0), along='X', du=0.375)
    Kt.add(g_box(0.07, 0.075, 0.085, bevel=0.01), "RustIron", loc=(-0.22, 0, 0))
    rivet(Kt, (-0.22, -0.038, 0), r=0.014, h=0.01)
    Kt.add(g_box(0.14, 0.068, 0.078, bevel=0.006), "RustRed", loc=(0.16, 0, 0))
    for x in (0.1, 0.14, 0.18, 0.22):
        Kt.add(g_box(0.008, 0.07, 0.08), "RustIronDark", loc=(x, 0, 0), rot=(0, 0.25, 0))
    return Kt.finish()


MODELS = [
    ("Chain_Long", chain_long),
    ("Gantry_Rail", gantry_rail),
    ("Magnet_Head", magnet_head),
    ("Steam_Vent", steam_vent),
    ("Press_Frame", press_frame),
    ("Press_Ram", press_ram),
    ("Garbage_Chute", garbage_chute),
    ("Loot_Nails", loot_nails),
    ("Loot_Plate", loot_plate),
    ("Loot_Chain", loot_chain),
    ("Loot_Handle", loot_handle),
]


def main():
    only = C.args_after_dashdash()
    C.reset_scene()
    _state_materials()
    report = []
    for name, build in MODELS:
        if only and name not in only:
            continue
        RNG.seed(zlib.crc32(name.encode()))
        o = build(name)
        o.name = name
        tris = K.tri_count(o)
        path = os.path.join(OUT, name + ".glb")
        K.export(path, o)
        report.append((name, tris, os.path.getsize(path), K.bbox_godot(o)))
    print("MODEL              TRIS  BUDGET      BYTES   X-range        Y-range        Z-range (Godot)")
    bad = []
    for name, tris, size, (bx, by, bz) in report:
        over = tris > BUDGET[name]
        if over:
            bad.append(name)
        print("%-16s %6d %7d %10d   [%5.2f %5.2f]  [%5.2f %5.2f]  [%5.2f %5.2f]%s" % (
            name, tris, BUDGET[name], size, bx[0], bx[1], by[0], by[1], bz[0], bz[1], "  OVER BUDGET" if over else ""))
    print("FLAT (временные плоские материалы):", ", ".join(sorted(K.FLAT_USED)) if K.FLAT_USED else "нет — все PBR")
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


main()
