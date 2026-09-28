#!/usr/bin/env python3
"""Процедурный набор PBR-текстур по листу R21 (docs/refs/R21-a-materials-palette.jpg) — запекается в Blender.

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/textures.py -- [имена…] [size=N] [samples=N]
        → godot/assets/textures/pbr/<name>/{albedo,roughness,normal[,metallic]}.png  (2048² дерево/камень/железо, 1024² остальное)
        → godot/assets/textures/decals/crown.png (силуэт короны, RGBA 512², numpy)
        без имён — все материалы; size=512 — быстрый черновик.
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/textures.py -- --test-glb
        → godot/assets/models/_texture_test.glb (проверка экспорта: куб stone, цилиндр wood, шар iron, ткань + корона, верёвка,
          крашеный ящик, тёмная балка) — смотреть через godot/tests/materials_snapshot.tscn, затем удалить.
    python3 godot/tools/blender/textures.py --contact        (системный python3 + Pillow, без Blender)
        → godot/tests/materials_contact.png (все albedo в ряд + roughness/normal) и godot/tests/materials_tiling.png (каждый albedo 2×2)

Рецепт запекания: Cycles, плоскость 2×2 м с UV 0..1; каждый канал — EMIT (цвет/шероховатость/металличность подаются в Emission,
без шума), нормали — bake NORMAL (TANGENT) с Bump-нодой, которую кормит карта высот. Бесшовность: все шумы/Voronoi берут
4D-координату на торе (cos u, sin u, cos v | sin v) — противоположные края тайла совпадают; структурные узоры (доски, кладка,
переплетение, пряди) — периодические функции с целым числом повторов на тайл.

Соглашения: 1 тайл = 1 м (uv_box/uv_cylinder_along в common.py); волокна дерева и пряди верёвки идут вдоль V (вверх картинки).
Верёвка: U = полный обхват (uv_cylinder_along(..., around=1)), 4 витка на тайл — для каната ⌀4 см брать scale≈4.
Цвета палитры — sRGB 0..255 (srgb() переводит в linear для нод).

Материалы: wood (4 доски по 25 см на тайл), wood_dark (3 доски), painted_red/blue/white (облупленная краска по доскам),
iron (+metallic.png = 0.9), fabric, fabric_red, fabric_blue (мешковина, 56 нитей/м), rope, stone (кладка 4 ряда × 2 блока
50×25 см с перевязкой — квадратные 25 см блоки читались как кафель). Все выходы (кроме albedo) — Non-Color; нормали в
OpenGL-конвенции (+Y вверх), как ждёт Godot. Первый запуск с GPU (Metal) компилирует ядра Cycles ~2–3 мин, дальше
~10–40 с на материал; TEX_GPU=0 — считать на CPU.
"""
import math
import os
import sys
import time

try:
    import bpy
except ImportError:  # системный python: только контактный лист / корона
    bpy = None
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PBR = os.path.join(GODOT, "assets", "textures", "pbr")
DECALS = os.path.join(GODOT, "assets", "textures", "decals")
TESTS = os.path.join(GODOT, "tests")
TEST_GLB = os.path.join(GODOT, "assets", "models", "_texture_test.glb")
TAU = 2.0 * math.pi


def srgb(r, g, b, a=1.0):
    """sRGB 0..255 → linear RGBA (цвета нод Blender — scene linear)."""
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), a)


# ----------------------------------------------------------------------------------------------------------------------
# Мини-DSL над нодами шейдера
# ----------------------------------------------------------------------------------------------------------------------
class NB:
    """Аргументы методов — сокеты или числа/кортежи; возвращаются выходные сокеты. u, v — UV плоскости (0..1)."""

    def __init__(self, nt):
        self.nt = nt
        self.count = 0
        uvn = self.new('ShaderNodeUVMap')
        sep = self.new('ShaderNodeSeparateXYZ')
        nt.links.new(uvn.outputs['UV'], sep.inputs[0])
        self.u = sep.outputs['X']
        self.v = sep.outputs['Y']

    # --- инфраструктура ---
    def new(self, typ, **props):
        node = self.nt.nodes.new(typ)
        for k, val in props.items():
            setattr(node, k, val)
        self.count += 1
        node.location = ((self.count % 40) * 200, -(self.count // 40) * 400)
        return node

    def plug(self, sock, val):
        if val is None:
            return
        if isinstance(val, bpy.types.NodeSocket):
            self.nt.links.new(val, sock)
            return
        if sock.type == 'VALUE':
            sock.default_value = float(val)
        elif sock.type == 'RGBA':
            if isinstance(val, (int, float)):
                sock.default_value = (val, val, val, 1.0)
            else:
                sock.default_value = tuple(val) if len(val) == 4 else tuple(val) + (1.0,)
        elif sock.type == 'VECTOR':
            if isinstance(val, (int, float)):
                sock.default_value = (val, val, val)
            else:
                sock.default_value = tuple(val)[:3]

    # --- скаляры ---
    def math(self, op, a, b=None, c=None, clamp=False):
        node = self.new('ShaderNodeMath', operation=op, use_clamp=clamp)
        self.plug(node.inputs[0], a)
        self.plug(node.inputs[1], b)
        self.plug(node.inputs[2], c)
        return node.outputs[0]

    def add(self, a, b):
        return self.math('ADD', a, b)

    def sub(self, a, b):
        return self.math('SUBTRACT', a, b)

    def mul(self, a, b):
        return self.math('MULTIPLY', a, b)

    def mad(self, a, b, c):
        """a*b + c"""
        return self.math('MULTIPLY_ADD', a, b, c)

    def fract(self, a):
        return self.math('FRACT', a)

    def floor(self, a):
        return self.math('FLOOR', a)

    def absv(self, a):
        return self.math('ABSOLUTE', a)

    def sin(self, a):
        return self.math('SINE', a)

    def cos(self, a):
        return self.math('COSINE', a)

    def pow(self, a, e):
        return self.math('POWER', a, e)

    def minv(self, a, b):
        return self.math('MINIMUM', a, b)

    def maxv(self, a, b):
        return self.math('MAXIMUM', a, b)

    def gt(self, a, t):
        return self.math('GREATER_THAN', a, t)

    def fmod(self, a, m):
        return self.math('FLOORED_MODULO', a, m)

    def clamp01(self, a):
        return self.math('ADD', a, 0.0, clamp=True)

    def sstep(self, x, e0, e1):
        """smoothstep(e0, e1, x); e0 > e1 — инверсия."""
        node = self.new('ShaderNodeMapRange', data_type='FLOAT', interpolation_type='SMOOTHSTEP', clamp=True)
        self.plug(node.inputs['Value'], x)
        self.plug(node.inputs['From Min'], e0)
        self.plug(node.inputs['From Max'], e1)
        node.inputs['To Min'].default_value = 0.0
        node.inputs['To Max'].default_value = 1.0
        return node.outputs['Result']

    def lerp(self, a, b, t):
        node = self.new('ShaderNodeMix', data_type='FLOAT', clamp_factor=True)
        self.plug(node.inputs[0], t)
        self.plug(node.inputs[2], a)
        self.plug(node.inputs[3], b)
        return node.outputs[0]

    def lin(self, terms, bias=0.0):
        """Сумма k_i * x_i + bias (x_i — сокеты или числа)."""
        acc = None
        for k, x in terms:
            acc = self.mad(x, k, acc if acc is not None else bias)
        return acc if acc is not None else bias

    # --- цвета ---
    def mixc(self, a, b, t, blend='MIX'):
        node = self.new('ShaderNodeMix', data_type='RGBA', blend_type=blend, clamp_factor=True)
        self.plug(node.inputs[0], t)
        self.plug(node.inputs[6], a)
        self.plug(node.inputs[7], b)
        return node.outputs[2]

    def scalec(self, col, k):
        """col × k (k — число или скалярный сокет: float→RGBA конвертируется неявно)."""
        return self.mixc(col, k, 1.0, 'MULTIPLY')

    def sepc(self, col):
        node = self.new('ShaderNodeSeparateColor', mode='RGB')
        self.plug(node.inputs[0], col)
        return node.outputs[0], node.outputs[1], node.outputs[2]

    def ramp(self, fac, stops, interp='LINEAR'):
        node = self.new('ShaderNodeValToRGB')
        cr = node.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            el.color = tuple(col) if len(col) == 4 else tuple(col) + (1.0,)
        self.plug(node.inputs['Fac'], fac)
        return node.outputs['Color']

    # --- бесшовные шумы: точка на 4D-торе ---
    def torus(self, fu, fv, seed=0.0, u=None, v=None):
        """UV → (x,y,z), w на торе Клиффорда; fu/fv — число «единиц шума» на тайл вдоль u/v (частота)."""
        u = self.u if u is None else u
        v = self.v if v is None else v
        ru, rv = fu / TAU, fv / TAU
        au, av = self.mul(u, TAU), self.mul(v, TAU)
        x = self.mad(self.cos(au), ru, seed * 1.73)
        y = self.mul(self.sin(au), ru)
        z = self.mad(self.cos(av), rv, seed * 0.91)
        w = self.mul(self.sin(av), rv)
        comb = self.new('ShaderNodeCombineXYZ')
        self.plug(comb.inputs[0], x)
        self.plug(comb.inputs[1], y)
        self.plug(comb.inputs[2], z)
        return comb.outputs[0], w

    def noise(self, fu, fv, detail=2.0, rough=0.5, seed=0.0, u=None, v=None, distortion=0.0):
        vec, w = self.torus(fu, fv, seed, u, v)
        node = self.new('ShaderNodeTexNoise', noise_dimensions='4D')
        node.inputs['Scale'].default_value = 1.0
        node.inputs['Detail'].default_value = detail
        node.inputs['Roughness'].default_value = rough
        node.inputs['Distortion'].default_value = distortion
        self.plug(node.inputs['Vector'], vec)
        self.plug(node.inputs['W'], w)
        return node.outputs['Fac']

    def voronoi(self, fu, fv, feature='F1', randomness=1.0, seed=0.0, u=None, v=None):
        """Возвращает ноду (outputs: Distance, Color, Position). Расстояние — в единицах шума (1 тайл = fu единиц по u)."""
        vec, w = self.torus(fu, fv, seed, u, v)
        node = self.new('ShaderNodeTexVoronoi', voronoi_dimensions='4D', feature=feature)
        node.inputs['Scale'].default_value = 1.0
        node.inputs['Randomness'].default_value = randomness
        self.plug(node.inputs['Vector'], vec)
        self.plug(node.inputs['W'], w)
        return node

    def white(self, a, b=0.0, seed=0.0):
        """Хэш 0..1 от (a, b, seed) — постоянен внутри доски/блока/нити."""
        comb = self.new('ShaderNodeCombineXYZ')
        self.plug(comb.inputs[0], a)
        self.plug(comb.inputs[1], b)
        self.plug(comb.inputs[2], seed)
        node = self.new('ShaderNodeTexWhiteNoise', noise_dimensions='3D')
        self.plug(node.inputs['Vector'], comb.outputs[0])
        return node.outputs['Value']


# ----------------------------------------------------------------------------------------------------------------------
# Материалы: каждый возвращает dict(color, rough, height, bump[, metal])
# ----------------------------------------------------------------------------------------------------------------------
WOOD = dict(early=srgb(184, 122, 64), late=srgb(112, 64, 28), knot=srgb(54, 30, 12), seam=srgb(40, 24, 12), crack=srgb(34, 20, 10))
WOOD_DARK = dict(early=srgb(112, 74, 42), late=srgb(66, 40, 20), knot=srgb(34, 18, 8), seam=srgb(24, 14, 8), crack=srgb(22, 12, 6))


def wood_nodes(nb, planks=4, pal=WOOD, rings=9.0, seed=0.0):
    """Доски вдоль V: годовые кольца (растянутый шум + «соборные» дуги), по сучку-эллипсу на часть досок с огибанием
    волокон, продольные трещины, тёмные швы и скруглённые кромки досок."""
    u, v = nb.u, nb.v
    pu = nb.mul(u, planks)
    pid = nb.floor(pu)
    ul = nb.fract(pu)
    h1 = nb.white(pid, 1.0, seed)
    h2 = nb.white(pid, 2.0, seed)
    h3 = nb.white(pid, 3.0, seed)
    h4 = nb.white(pid, 4.0, seed)
    v2 = nb.add(v, nb.mul(h2, 3.0))                       # свой сдвиг рисунка у каждой доски
    # сучок: эллипс в координатах доски (центр по ширине ± , по длине — hash), не на каждой доске
    ksel = nb.gt(h3, 0.45)
    du = nb.mul(nb.sub(ul, nb.mad(h4, 0.4, 0.3)), 1.0 / planks)          # м поперёк
    dv = nb.sub(nb.fract(nb.add(nb.sub(v, h4), 0.5)), 0.5)              # м вдоль, периодично
    kd = nb.pow(nb.add(nb.pow(nb.mul(du, 1.0 / 0.030), 2.0), nb.pow(nb.mul(dv, 1.0 / 0.055), 2.0)), 0.5)
    knot = nb.mul(nb.sstep(kd, 1.0, 0.55), ksel)
    kring = nb.mul(nb.mul(nb.sstep(nb.fract(nb.mul(kd, 3.0)), 0.6, 0.9), nb.sstep(kd, 1.6, 1.0)), ksel)
    bend = nb.mul(nb.sstep(kd, 4.0, 1.0), ksel)
    # кольца: координата r = ul*rings + сдвиг доски + изгиб шумом + дуга + огибание сучка
    warp = nb.noise(4.0, 0.8, detail=3.0, rough=0.55, seed=seed + 1, v=v2)
    warp2 = nb.noise(14.0, 2.0, detail=2.0, rough=0.5, seed=seed + 6, v=v2)
    arc = nb.cos(nb.mad(v2, TAU, nb.mul(h1, 6.0)))
    r = nb.lin([(rings, ul), (7.0, h1), (2.6, warp), (0.5, warp2), (1.1, arc), (2.5, bend)], bias=-1.5)
    t = nb.fract(r)
    width = nb.noise(2.0, 1.0, detail=1.0, seed=seed + 7, v=v2)
    latew = nb.sstep(t, nb.mad(width, 0.3, 0.45), 0.93)
    fine = nb.noise(90.0, 5.0, detail=2.0, rough=0.6, seed=seed + 2, v=v2)
    age = nb.noise(1.5, 1.0, detail=3.0, rough=0.5, seed=seed + 8, v=v2)
    cr1 = nb.noise(45.0, 0.9, detail=2.0, rough=0.5, seed=seed + 4, v=v2)
    cr2 = nb.noise(3.0, 1.2, detail=2.0, rough=0.5, seed=seed + 5, v=v2)
    crack = nb.mul(nb.sstep(cr1, 0.70, 0.745), nb.sstep(cr2, 0.50, 0.62))
    e = nb.absv(nb.sub(ul, 0.5))
    seamm = nb.sstep(e, 0.465, 0.49)
    bev = nb.sstep(e, 0.40, 0.475)
    # цвет
    col = nb.mixc(pal['early'], pal['late'], latew)
    col = nb.scalec(col, nb.mad(h1, 0.30, 0.85))
    col = nb.scalec(col, nb.mad(fine, 0.26, 0.87))
    col = nb.scalec(col, nb.mad(age, 0.30, 0.85))
    col = nb.mixc(col, pal['knot'], nb.clamp01(nb.lin([(0.9, knot), (0.55, kring)])))
    col = nb.mixc(col, pal['crack'], crack)
    col = nb.scalec(col, nb.sub(1.0, nb.mul(bev, 0.22)))
    col = nb.mixc(col, pal['seam'], seamm)
    height = nb.lin([(0.12, fine), (-0.18, latew), (0.12, knot), (-0.08, kring), (-0.45, crack), (-0.40, bev), (-0.50, seamm)], bias=0.55)
    rough = nb.clamp01(nb.lin([(0.16, latew), (0.10, fine), (0.25, crack), (0.20, seamm), (-0.10, knot)], bias=0.58))
    return dict(color=col, rough=rough, height=height, bump=0.02, seam=seamm)


def painted_nodes(nb, paint, seed=0.0):
    """Облупленная краска поверх досок: жёсткий порог шума, в сколах — потемневшее дерево, слой краски приподнят."""
    w = wood_nodes(nb, planks=4, seed=seed)
    m1 = nb.noise(3.2, 3.2, detail=6.0, rough=0.62, seed=seed + 10)
    m2 = nb.noise(16.0, 16.0, detail=2.0, rough=0.5, seed=seed + 11)
    m = nb.lin([(1.0, m1), (0.12, m2), (-0.30, w['seam'])], bias=-0.06)
    pm = nb.sstep(m, 0.41, 0.425)                        # 1 = краска на месте
    rim = nb.sstep(m, 0.425, 0.46)
    edge = nb.mul(pm, nb.sub(1.0, rim))                   # узкая кромка скола
    var = nb.noise(7.0, 7.0, detail=3.0, rough=0.5, seed=seed + 12)
    grime = nb.noise(2.5, 2.5, detail=4.0, rough=0.55, seed=seed + 13)
    scuff = nb.noise(60.0, 4.0, detail=1.0, rough=0.5, seed=seed + 14)
    pc = nb.scalec(paint, nb.mad(var, 0.28, 0.84))
    pc = nb.scalec(pc, nb.mad(grime, 0.30, 0.82))
    pc = nb.scalec(pc, nb.mad(scuff, 0.10, 0.95))
    woodc = nb.scalec(w['color'], 0.78)
    col = nb.mixc(woodc, pc, pm)
    col = nb.scalec(col, nb.sub(1.0, nb.mul(edge, 0.30)))
    height = nb.lin([(0.35, w['height']), (0.55, pm)], bias=0.05)
    rough = nb.lerp(0.74, nb.mad(var, 0.18, 0.40), pm)
    return dict(color=col, rough=rough, height=height, bump=0.010)


def iron_nodes(nb, seed=0.0):
    """Тёмный серо-синий металл: шлифовка вдоль V, крупные пятна износа, ржавые пятна с рыхлой кромкой и потёками,
    ямки коррозии, короткие тонкие царапины (рёбра Voronoi, порезанные маской)."""
    brushed = nb.noise(140.0, 6.0, detail=1.0, rough=0.5, seed=seed + 1)
    wear = nb.noise(1.6, 1.6, detail=3.0, rough=0.5, seed=seed + 10)
    blotch = nb.noise(2.4, 2.4, detail=6.0, rough=0.68, seed=seed + 2)
    blotch2 = nb.noise(9.0, 9.0, detail=3.0, rough=0.5, seed=seed + 3)
    drip = nb.noise(12.0, 1.2, detail=2.0, rough=0.5, seed=seed + 11)        # потёки вниз (вдоль V)
    rustf = nb.lin([(1.0, blotch), (0.22, blotch2), (0.10, drip)], bias=-0.16)
    density = nb.sstep(rustf, 0.42, 0.68)                                     # плотность коррозии 0..1
    speck = nb.noise(36.0, 36.0, detail=3.0, rough=0.6, seed=seed + 13)
    rustm = nb.sstep(nb.lin([(1.0, speck), (0.55, density)], bias=0.0), 0.70, 0.76)   # крапины срастаются в пятна
    halo = nb.sstep(rustf, 0.34, 0.52)                                        # ореол вокруг пятна
    spk = nb.noise(70.0, 70.0, detail=1.0, rough=0.5, seed=seed + 4)
    flake = nb.noise(48.0, 48.0, detail=3.0, rough=0.6, seed=seed + 5)
    grime = nb.noise(4.0, 4.0, detail=3.0, rough=0.5, seed=seed + 6)
    pitv = nb.voronoi(45.0, 45.0, seed=seed + 7)
    pit = nb.mul(nb.sstep(pitv.outputs['Distance'], 0.30, 0.12), nb.mad(halo, 0.7, 0.3))
    pit = nb.mul(pit, nb.gt(nb.sepc(pitv.outputs['Color'])[0], 0.45))
    scr = nb.voronoi(7.0, 7.0, feature='DISTANCE_TO_EDGE', seed=seed + 8)
    segs = nb.mul(nb.gt(nb.noise(5.0, 5.0, detail=1.0, seed=seed + 9), 0.58), nb.gt(nb.noise(24.0, 24.0, detail=1.0, seed=seed + 12), 0.45))
    scratch = nb.mul(nb.sstep(scr.outputs['Distance'], 0.012, 0.0), segs)
    scratch = nb.mul(scratch, nb.sub(1.0, rustm))
    metal = nb.scalec(srgb(66, 70, 82), nb.mad(brushed, 0.30, 0.85))
    metal = nb.scalec(metal, nb.mad(grime, 0.45, 0.72))
    metal = nb.scalec(metal, nb.mad(wear, 0.6, 0.7))
    metal = nb.mixc(metal, srgb(78, 60, 46), nb.mul(halo, 0.5))
    rust = nb.mixc(srgb(74, 36, 16), srgb(166, 92, 36), nb.mul(spk, flake))
    rust = nb.scalec(rust, nb.mad(flake, 0.5, 0.75))
    col = nb.mixc(metal, rust, rustm)
    col = nb.mixc(col, srgb(128, 132, 142), nb.mul(scratch, 0.55))
    col = nb.mixc(col, srgb(30, 18, 10), nb.mul(pit, 0.7))
    rough = nb.clamp01(nb.lerp(nb.lin([(0.15, brushed), (0.20, grime), (0.15, halo)], bias=0.28), 0.88, rustm))
    rough = nb.clamp01(nb.lin([(1.0, rough), (0.10, pit), (-0.15, scratch)]))
    rustbump = nb.mul(rustm, flake)
    height = nb.lin([(0.05, brushed), (0.35, rustbump), (0.12, rustm), (-0.45, pit), (-0.30, scratch)], bias=0.5)
    return dict(color=col, rough=rough, height=height, bump=0.016, metal=0.9)


def fabric_nodes(nb, base=srgb(206, 186, 150), seed=0.0, threads=56):
    """Мешковина: переплетение нитей (над/под), слегка волнистое, отдельный оттенок у каждой нити, ворс, грязь."""
    u, v = nb.u, nb.v
    du = nb.mul(nb.sub(nb.noise(2.0, 2.0, detail=2.0, seed=seed + 1), 0.5), 0.007)
    dv = nb.mul(nb.sub(nb.noise(2.0, 2.0, detail=2.0, seed=seed + 2), 0.5), 0.007)
    cu = nb.mul(nb.add(u, du), threads)
    cv = nb.mul(nb.add(v, dv), threads)
    i = nb.fmod(nb.floor(cu), threads)
    j = nb.fmod(nb.floor(cv), threads)
    fu_, fv_ = nb.fract(cu), nb.fract(cv)
    over = nb.fmod(nb.add(i, j), 2.0)                    # 0: нить вдоль V сверху, 1: вдоль U
    pw = nb.sin(nb.mul(fu_, math.pi))
    pf = nb.sin(nb.mul(fv_, math.pi))
    top = nb.lerp(pw, pf, over)
    under = nb.mul(nb.lerp(pf, pw, over), 0.45)
    h = nb.maxv(top, under)
    fib = nb.noise(240.0, 240.0, detail=1.0, seed=seed + 3)
    tw = nb.white(i, 0.0, seed + 4)
    tf = nb.white(j, 1.0, seed + 4)
    shade = nb.mad(nb.lerp(tw, tf, over), 0.14, 0.93)
    dirt = nb.noise(3.0, 3.0, detail=4.0, rough=0.55, seed=seed + 5)
    col = nb.scalec(base, shade)
    col = nb.scalec(col, nb.mad(h, 0.45, 0.55))
    col = nb.scalec(col, nb.mad(dirt, 0.30, 0.85))
    col = nb.scalec(col, nb.mad(fib, 0.12, 0.94))
    rough = nb.clamp01(nb.lin([(-0.10, h)], bias=0.96))
    height = nb.lin([(0.80, h), (0.10, fib)], bias=0.05)
    return dict(color=col, rough=rough, height=height, bump=0.009)


def rope_nodes(nb, strands=3, twists=4, base=srgb(178, 138, 86), dark=srgb(70, 50, 26), seed=0.0):
    """Витой канат: U — обхват, V — вдоль; пряди-винты (целое число витков на тайл), волокна вдоль пряди, ворс."""
    u, v = nb.u, nb.v
    psi = nb.fract(nb.mad(nb.sub(u, nb.mul(v, twists)), strands, 0.5))   # 0.5 — центр пряди
    prof = nb.pow(nb.sin(nb.mul(psi, math.pi)), 0.7)
    fwob = nb.mul(nb.sub(nb.noise(6.0, 30.0, detail=2.0, seed=seed + 1), 0.5), 0.5)
    fib = nb.mad(nb.sin(nb.mul(nb.add(nb.mul(psi, 7.0), fwob), TAU)), 0.5, 0.5)
    fib = nb.pow(fib, 2.0)
    hair = nb.noise(40.0, 160.0, detail=1.0, seed=seed + 2)
    var = nb.noise(1.5, 6.0, detail=3.0, rough=0.5, seed=seed + 3)
    col = nb.mixc(dark, base, nb.pow(prof, 0.6))
    col = nb.scalec(col, nb.mad(var, 0.36, 0.82))
    col = nb.scalec(col, nb.mad(nb.mul(fib, prof), 0.20, 0.90))
    col = nb.scalec(col, nb.mad(hair, 0.16, 0.92))
    height = nb.lin([(0.85, prof), (0.08, nb.mul(fib, prof)), (0.05, hair)])
    rough = nb.lin([(-0.10, prof)], bias=0.92)
    return dict(color=col, rough=rough, height=height, bump=0.03)


def stone_nodes(nb, rows=4, cols=2, seed=0.0):
    """Известняковая кладка (блоки 1/cols × 1/rows м, перевязка в полблока): швы раствора утоплены, у блоков
    скруглённые обитые кромки и свой выступ, пятнистость, поры, редкие трещины; мох — редкими пятнами в швах и у кромок."""
    u, v = nb.u, nb.v
    rv = nb.mul(v, rows)
    j = nb.floor(rv)
    off = nb.mul(nb.fmod(j, 2.0), 0.5)
    ru = nb.add(nb.mul(u, cols), off)
    i = nb.fmod(nb.floor(ru), cols)
    lu, lv = nb.fract(ru), nb.fract(rv)
    hb = nb.white(i, j, seed + 1)
    hb2 = nb.white(i, j, seed + 2)
    hb3 = nb.white(i, j, seed + 3)
    wob = nb.mul(nb.sub(nb.noise(24.0, 24.0, detail=3.0, rough=0.6, seed=seed + 3), 0.5), 0.09)
    chip = nb.mul(nb.sstep(nb.noise(9.0, 9.0, detail=2.0, seed=seed + 11), 0.64, 0.78), 0.07)   # обитые углы/кромки
    eu = nb.add(nb.minv(lu, nb.sub(1.0, lu)), nb.mul(wob, 0.5))       # блок 2× шире: шов той же толщины в метрах
    ev = nb.add(nb.minv(lv, nb.sub(1.0, lv)), wob)
    e = nb.sub(nb.minv(eu, nb.mul(ev, 0.5)), chip)                    # расстояние до кромки в долях ширины блока
    mw = 0.022
    blockm = nb.sstep(e, mw, mw + 0.02)                                # 1 внутри блока
    bev = nb.pow(nb.sstep(e, mw, mw + 0.10), 0.55)                     # скруглённое плечо
    mottle = nb.noise(8.0, 8.0, detail=4.0, rough=0.55, seed=seed + 4)
    mottle2 = nb.noise(3.0, 3.0, detail=2.0, rough=0.5, seed=seed + 12)
    fine = nb.noise(60.0, 60.0, detail=3.0, rough=0.6, seed=seed + 5)
    bulge = nb.noise(5.0, 5.0, detail=1.0, seed=seed + 6)
    pitv = nb.voronoi(55.0, 55.0, seed=seed + 7)
    pit = nb.mul(nb.sstep(pitv.outputs['Distance'], 0.34, 0.12), nb.gt(nb.sepc(pitv.outputs['Color'])[0], 0.55))
    # трещины: тонкие вытянутые вдоль U штрихи (растянутый шум с жёстким порогом), только на части блоков
    crn = nb.noise(1.2, 40.0, detail=2.0, rough=0.5, seed=seed + 8)
    crack = nb.mul(nb.sstep(crn, 0.74, 0.77), nb.gt(nb.noise(3.0, 3.0, detail=1.0, seed=seed + 9), 0.62))
    crack = nb.mul(crack, nb.mul(blockm, nb.gt(hb3, 0.6)))
    mossn = nb.noise(3.0, 3.0, detail=5.0, rough=0.6, seed=seed + 10)
    mossl = nb.noise(1.2, 1.2, detail=1.0, seed=seed + 13)
    mossw = nb.mul(nb.sstep(nb.lin([(0.7, mossn), (0.5, mossl)], bias=-0.1), 0.52, 0.66), nb.sub(1.0, nb.sstep(e, mw, mw + 0.13)))
    block = nb.scalec(nb.mixc(srgb(186, 176, 154), srgb(198, 172, 130), hb2), nb.mad(hb, 0.36, 0.80))
    block = nb.mixc(block, srgb(150, 148, 140), nb.mul(mottle2, 0.5))
    block = nb.scalec(block, nb.mad(mottle, 0.30, 0.85))
    block = nb.scalec(block, nb.mad(fine, 0.16, 0.92))
    mgrain = nb.noise(120.0, 120.0, detail=2.0, rough=0.6, seed=seed + 14)
    mortar = nb.scalec(srgb(132, 124, 108), nb.mad(fine, 0.36, 0.70))
    mortar = nb.scalec(mortar, nb.mad(mgrain, 0.30, 0.85))
    col = nb.mixc(mortar, block, blockm)
    mosst = nb.noise(45.0, 45.0, detail=2.0, rough=0.6, seed=seed + 15)
    moss = nb.mixc(srgb(70, 92, 36), srgb(124, 136, 62), mosst)
    col = nb.mixc(col, moss, nb.mul(mossw, nb.mad(mosst, 0.4, 0.6)))
    col = nb.mixc(col, srgb(56, 50, 42), nb.clamp01(nb.lin([(0.8, crack), (0.6, pit)])))
    face = nb.lin([(0.18, hb), (0.10, bulge)], bias=0.52)
    height = nb.lin([(1.0, nb.mul(face, bev)), (0.05, fine), (-0.10, pit), (-0.15, crack), (0.03, mossw)], bias=0.02)
    rough = nb.lerp(0.95, nb.mad(fine, 0.10, 0.80), blockm)
    rough = nb.clamp01(nb.lin([(1.0, rough), (0.05, mossw), (0.1, pit)]))
    return dict(color=col, rough=rough, height=height, bump=0.03)


PAINT_RED = srgb(170, 44, 36)
PAINT_BLUE = srgb(56, 86, 150)
PAINT_WHITE = srgb(216, 206, 182)

MATERIALS = {
    # name: (builder, size)
    'wood': (lambda nb: wood_nodes(nb, planks=4, pal=WOOD, seed=0.0), 2048),
    'wood_dark': (lambda nb: wood_nodes(nb, planks=3, pal=WOOD_DARK, rings=8.0, seed=5.0), 2048),
    'painted_red': (lambda nb: painted_nodes(nb, PAINT_RED, seed=1.0), 1024),
    'painted_blue': (lambda nb: painted_nodes(nb, PAINT_BLUE, seed=2.0), 1024),
    'painted_white': (lambda nb: painted_nodes(nb, PAINT_WHITE, seed=3.0), 1024),
    'iron': (lambda nb: iron_nodes(nb, seed=0.0), 2048),
    'fabric': (lambda nb: fabric_nodes(nb, srgb(206, 186, 150), seed=0.0), 1024),
    'fabric_red': (lambda nb: fabric_nodes(nb, srgb(172, 52, 44), seed=1.0), 1024),
    'fabric_blue': (lambda nb: fabric_nodes(nb, srgb(64, 86, 142), seed=2.0), 1024),
    'rope': (lambda nb: rope_nodes(nb, seed=0.0), 1024),
    'stone': (lambda nb: stone_nodes(nb, seed=0.0), 2048),
}


# ----------------------------------------------------------------------------------------------------------------------
# Запекание
# ----------------------------------------------------------------------------------------------------------------------
def _setup_cycles(samples):
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = samples
    scn.cycles.use_adaptive_sampling = False
    scn.cycles.use_denoising = False
    scn.view_settings.view_transform = 'Standard'
    scn.render.bake.use_pass_direct = False
    scn.render.bake.use_pass_indirect = False
    scn.render.bake.use_pass_color = True
    scn.render.bake.margin = 0
    scn.render.bake.use_clear = True
    scn.render.bake.use_selected_to_active = False
    scn.render.bake.normal_space = 'TANGENT'
    scn.cycles.device = 'CPU'
    if os.environ.get('TEX_GPU', '1') == '1':
        try:
            prefs = bpy.context.preferences.addons['cycles'].preferences
            prefs.compute_device_type = 'METAL'
            prefs.get_devices()
            for dev in prefs.devices:
                dev.use = dev.type != 'CPU'
            scn.cycles.device = 'GPU'
        except Exception as exc:  # noqa: BLE001
            print('GPU unavailable, CPU:', exc)
    return scn


def _linear_to_srgb8(a):
    a = np.clip(a, 0.0, 1.0)
    s = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1.0 / 2.4) - 0.055)
    return np.clip(np.rint(s * 255.0), 0, 255).astype(np.uint8)


def _read_float(img):
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)


def save_rgba8(path, arr8_bottom_up, alpha=False):
    """uint8 HxWx4 (строки снизу вверх, как в Blender) → PNG через байтовое изображение Blender (без цветокоррекции)."""
    h, w = arr8_bottom_up.shape[:2]
    img = bpy.data.images.new('__out', w, h, alpha=alpha, float_buffer=False)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    flat = (arr8_bottom_up.astype(np.float32) / 255.0).reshape(-1)
    img.pixels.foreach_set(flat)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def bake_material(name, build, size, samples=4):
    """Плоскость 2×2 м, UV 0..1; каналы albedo (EMIT, sRGB), roughness (EMIT, Non-Color), normal (NORMAL/TANGENT, Bump),
    metallic (EMIT константа, если у материала есть metal). Пишет PNG в assets/textures/pbr/<name>/."""
    t0 = time.time()
    out_dir = os.path.join(PBR, name)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = _setup_cycles(samples)
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    plane.name = 'Bake_' + name
    mat = bpy.data.materials.new('Bake_' + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    plane.data.materials.append(mat)
    nb = NB(nt)
    ch = build(nb)
    out = nb.new('ShaderNodeOutputMaterial')
    emit = nb.new('ShaderNodeEmission')
    emit.inputs['Strength'].default_value = 1.0
    bsdf = nb.new('ShaderNodeBsdfPrincipled')
    bump = nb.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 1.0
    bump.inputs['Distance'].default_value = ch['bump']
    nb.plug(bump.inputs['Height'], ch['height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    nb.plug(bsdf.inputs['Base Color'], ch['color'])
    nb.plug(bsdf.inputs['Roughness'], ch['rough'])
    tex = nb.new('ShaderNodeTexImage')
    nt.nodes.active = tex
    bpy.ops.object.select_all(action='DESELECT')
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane

    def bake(kind, source=None):
        img = bpy.data.images.new('__bake', size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = 'Non-Color'
        tex.image = img
        for l in list(out.inputs['Surface'].links):
            nt.links.remove(l)
        for l in list(emit.inputs['Color'].links):
            nt.links.remove(l)
        if kind == 'NORMAL':
            nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
            scn.cycles.samples = 1
            bpy.ops.object.bake(type='NORMAL')
        else:
            nb.plug(emit.inputs['Color'], source)
            nt.links.new(emit.outputs['Emission'], out.inputs['Surface'])
            scn.cycles.samples = samples
            bpy.ops.object.bake(type='EMIT')
        arr = _read_float(img)
        bpy.data.images.remove(img)
        return arr

    alb = bake('EMIT', ch['color'])
    a8 = _linear_to_srgb8(alb)
    a8[..., 3] = 255
    save_rgba8(os.path.join(out_dir, 'albedo.png'), a8)
    rough = bake('EMIT', ch['rough'])
    r8 = np.clip(np.rint(np.clip(rough, 0, 1) * 255.0), 0, 255).astype(np.uint8)
    r8[..., 1] = r8[..., 0]
    r8[..., 2] = r8[..., 0]
    r8[..., 3] = 255
    save_rgba8(os.path.join(out_dir, 'roughness.png'), r8)
    nrm = bake('NORMAL')
    n8 = np.clip(np.rint(np.clip(nrm, 0, 1) * 255.0), 0, 255).astype(np.uint8)
    n8[..., 3] = 255
    save_rgba8(os.path.join(out_dir, 'normal.png'), n8)
    if ch.get('metal') is not None:
        m8 = np.full((size, size, 4), int(round(ch['metal'] * 255)), dtype=np.uint8)
        m8[..., 3] = 255
        save_rgba8(os.path.join(out_dir, 'metallic.png'), m8)
    print('baked %-14s %4d² in %5.1fs  albedo mean sRGB %s  normal mean %s' % (
        name, size, time.time() - t0, a8[..., :3].reshape(-1, 3).mean(0).round(1), n8[..., :3].reshape(-1, 3).mean(0).round(1)))


# ----------------------------------------------------------------------------------------------------------------------
# Корона (декаль, numpy) — работает и в Blender, и в системном python
# ----------------------------------------------------------------------------------------------------------------------
def _vnoise(size, cells, seed, octaves=4):
    """Периодический value-noise (fBm) 0..1 размера size×size."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = rng.random((c, c))
        t = (np.arange(size) + 0.5) / size * c
        i0 = np.floor(t).astype(int) % c
        i1 = (i0 + 1) % c
        f = t - np.floor(t)
        f = f * f * (3 - 2 * f)
        fy, fx = f[:, None], f[None, :]
        val = (g[i0[:, None], i0[None, :]] * (1 - fx) + g[i0[:, None], i1[None, :]] * fx) * (1 - fy) + \
              (g[i1[:, None], i0[None, :]] * (1 - fx) + g[i1[:, None], i1[None, :]] * fx) * fy
        out += amp * val
        tot += amp
        amp *= 0.5
    return out / tot


def _poly_mask(x, y, pts):
    inside = np.zeros_like(x, dtype=bool)
    n = len(pts)
    for k in range(n):
        x1, y1 = pts[k]
        x2, y2 = pts[(k + 1) % n]
        cond = (y1 > y) != (y2 > y)
        xint = (x2 - x1) * (y - y1) / ((y2 - y1) + 1e-12) + x1
        inside ^= cond & (x < xint)
    return inside


def _erode(mask, k):
    m = mask.copy()
    for _ in range(k):
        m = m & np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    return m


def _blur3(a):
    return (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0


def crown_decal(path, size=512, seed=7):
    """Силуэт короны (три зубца с шариками, пояс с прорезями), кремовый, потёртые края → RGBA PNG (сверху вниз)."""
    yy, xx = np.mgrid[0:size, 0:size]
    x = (xx + 0.5) / size
    y = (yy + 0.5) / size
    body = _poly_mask(x, y, [(0.16, 0.86), (0.10, 0.36), (0.32, 0.56), (0.50, 0.14), (0.68, 0.56), (0.90, 0.36), (0.84, 0.86)])
    for cx, cy in [(0.10, 0.33), (0.50, 0.11), (0.90, 0.33)]:
        body |= (x - cx) ** 2 + (y - cy) ** 2 < 0.05 ** 2
    body |= (x > 0.13) & (x < 0.87) & (y > 0.72) & (y < 0.88)
    for cx in (0.30, 0.50, 0.70):
        body &= ~((x - cx) ** 2 + (y - 0.80) ** 2 < 0.028 ** 2)
    body &= ~((np.abs(x - 0.5) + np.abs(y - 0.58)) < 0.055)          # ромб в центре
    band_edge = (np.abs(y - 0.72) < 0.006) & (x > 0.16) & (x < 0.84)  # прорезь между поясом и телом
    body &= ~band_edge
    n1 = _vnoise(size, 6, seed)
    n2 = _vnoise(size, 40, seed + 1, octaves=2)
    edge = body & ~_erode(body, 9)
    alpha = body & ~(edge & (n1 * 0.6 + n2 * 0.4 < 0.46))
    alpha &= ~(n2 > 0.90)
    a = _blur3(alpha.astype(np.float32))
    a = _blur3(a)
    a *= (0.80 + 0.20 * n1).astype(np.float32)
    tone = 0.84 + 0.30 * _vnoise(size, 5, seed + 2)
    col = np.array([226, 214, 184], dtype=np.float32) / 255.0
    rgb = np.clip(col[None, None, :] * tone[..., None], 0, 1)
    dark = np.clip(1.0 - 0.35 * (edge & alpha), 0, 1)
    rgb *= dark[..., None]
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[..., :3] = np.rint(rgb * 255).astype(np.uint8)
    out[..., 3] = np.rint(np.clip(a, 0, 1) * 255).astype(np.uint8)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if bpy is not None:
        save_rgba8(path, out[::-1], alpha=True)
    else:
        from PIL import Image
        Image.fromarray(out, 'RGBA').save(path)
    print('crown decal', path, 'coverage %.0f%%' % (100 * (out[..., 3] > 127).mean()))


# ----------------------------------------------------------------------------------------------------------------------
# Тестовая сцена экспорта (проверка хелперов common.py + glTF)
# ----------------------------------------------------------------------------------------------------------------------
def build_test_glb():
    sys.path.insert(0, HERE)
    import common as C
    from mathutils import Matrix
    C.reset_scene()
    objs = []
    cube = C.add_cube('Stone_Cube', (0.8, 0.8, 0.8), (-1.75, 0.0, 0.4))
    C.uv_box(cube, 1.0)
    C.bevel(cube, 0.02, 2)
    C.smooth(cube)
    C.assign(cube, C.textured_material('Stone', 'stone'))
    objs.append(cube)
    cyl = C.add_cylinder('Wood_Cyl', radius=0.14, depth=1.3, loc=(-0.85, 0.0, 0.65), verts=32)
    C.uv_cylinder_along(cyl, 'Z', 1.0)
    C.bevel(cyl, 0.02, 2)
    C.smooth(cyl)
    C.assign(cyl, C.textured_material('Wood', 'wood'))
    objs.append(cyl)
    sph = C.add_sphere('Iron_Sphere', radius=0.38, loc=(0.0, 0.0, 0.38), segments=48, rings=24)
    C.uv_box(sph, 1.0)
    C.smooth(sph)
    C.assign(sph, C.textured_material('Iron', 'iron'))
    objs.append(sph)
    box = C.add_cube('Painted_Box', (0.6, 0.6, 0.6), (0.9, 0.0, 0.3))
    C.uv_box(box, 1.0)
    C.bevel(box, 0.015, 2)
    C.smooth(box)
    C.assign(box, C.textured_material('PaintedRed', 'painted_red'))
    objs.append(box)
    beam = C.add_cube('Dark_Beam', (1.2, 0.18, 0.18), (0.9, 0.0, 0.69))
    C.uv_box(beam, 1.0, along='X')
    C.bevel(beam, 0.012, 2)
    C.smooth(beam)
    C.assign(beam, C.textured_material('WoodDark', 'wood_dark'))
    objs.append(beam)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(1.95, 0.0, 0.6))
    cloth = bpy.context.active_object
    cloth.name = 'Fabric_Plane'
    cloth.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
    C.uv_box(cloth, 1.0)
    C.assign(cloth, C.textured_material('Fabric', 'fabric'))
    objs.append(cloth)
    crown = C.decal_plane('Crown_Decal', os.path.join(DECALS, 'crown.png'), (0.5, 0.5), (1.95, -0.01, 0.6))
    objs.append(crown)
    rope = C.add_cylinder('Rope', radius=0.035, depth=1.6, loc=(-0.2, -0.75, 0.035), verts=16, rot=(0.0, math.pi / 2, 0.0))
    C.apply_transforms(rope, rotation=True)
    C.uv_cylinder_along(rope, 'X', 4.0, around=1.0)
    C.smooth(rope)
    C.assign(rope, C.textured_material('Rope', 'rope'))
    objs.append(rope)
    for i, (nm, folder) in enumerate([('FabricRed', 'fabric_red'), ('FabricBlue', 'fabric_blue'), ('PaintedBlue', 'painted_blue'), ('PaintedWhite', 'painted_white')]):
        bpy.ops.mesh.primitive_plane_add(size=0.4, location=(-1.75 + i * 0.45, 0.0, 1.35))
        sw = bpy.context.active_object
        sw.name = 'Swatch_' + nm
        sw.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
        C.uv_box(sw, 1.0)
        C.assign(sw, C.textured_material(nm, folder))
        objs.append(sw)
    C.export_glb(TEST_GLB, objs)
    print(C.stats())


# ----------------------------------------------------------------------------------------------------------------------
# Контактный лист (Pillow, системный python)
# ----------------------------------------------------------------------------------------------------------------------
def contact_sheet():
    from PIL import Image, ImageDraw
    names = list(MATERIALS.keys())
    cell = 256
    pad = 8
    label_h = 18
    rows = ['albedo', 'roughness', 'normal']
    W = pad + len(names) * (cell + pad)
    H = pad + len(rows) * (cell + label_h + pad)
    sheet = Image.new('RGB', (W, H), (28, 28, 30))
    draw = ImageDraw.Draw(sheet)
    for ci, n in enumerate(names):
        for ri, ch in enumerate(rows):
            p = os.path.join(PBR, n, ch + '.png')
            x = pad + ci * (cell + pad)
            y = pad + ri * (cell + label_h + pad)
            if os.path.exists(p):
                im = Image.open(p).convert('RGB').resize((cell, cell), Image.LANCZOS)
                sheet.paste(im, (x, y + label_h))
            draw.text((x + 2, y + 2), '%s / %s' % (n, ch), fill=(230, 230, 230))
    out = os.path.join(TESTS, 'materials_contact.png')
    sheet.save(out)
    print('contact', out)
    # тайлинг 2×2 — швы видны сразу
    tile = 200
    W = pad + len(names) * (tile * 2 + pad)
    H = pad + label_h + tile * 2 + pad
    ts = Image.new('RGB', (W, H), (28, 28, 30))
    draw = ImageDraw.Draw(ts)
    for ci, n in enumerate(names):
        p = os.path.join(PBR, n, 'albedo.png')
        x = pad + ci * (tile * 2 + pad)
        if os.path.exists(p):
            im = Image.open(p).convert('RGB').resize((tile, tile), Image.LANCZOS)
            for dx in (0, 1):
                for dy in (0, 1):
                    ts.paste(im, (x + dx * tile, pad + label_h + dy * tile))
        draw.text((x + 2, pad), n + ' 2x2', fill=(230, 230, 230))
    out2 = os.path.join(TESTS, 'materials_tiling.png')
    ts.save(out2)
    print('tiling', out2)
    # корона на красном фоне
    cp = os.path.join(DECALS, 'crown.png')
    if os.path.exists(cp):
        cr = Image.open(cp).convert('RGBA')
        bg = Image.new('RGBA', cr.size, (150, 40, 34, 255))
        bg.alpha_composite(cr)
        bg.convert('RGB').save(os.path.join(TESTS, 'materials_crown.png'))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if '--contact' in argv:
        if not os.path.exists(os.path.join(DECALS, 'crown.png')):
            crown_decal(os.path.join(DECALS, 'crown.png'))
        contact_sheet()
        return
    if bpy is None:
        print('нужен Blender (или --contact для системного python)')
        sys.exit(2)
    if '--test-glb' in argv:
        build_test_glb()
        return
    size_override = None
    samples = 4
    names = []
    for a in argv:
        if a.startswith('size='):
            size_override = int(a.split('=')[1])
        elif a.startswith('samples='):
            samples = int(a.split('=')[1])
        elif a in MATERIALS:
            names.append(a)
        elif a != '--crown':
            print('неизвестный материал', a, 'доступны:', ', '.join(MATERIALS))
            sys.exit(2)
    if '--crown' in argv or not names:
        crown_decal(os.path.join(DECALS, 'crown.png'))
    if '--crown' in argv and not names:
        return
    for n in names or list(MATERIALS):
        build, size = MATERIALS[n]
        bake_material(n, build, size_override or size, samples)


# ----------------------------------------------------------------------------------------------------------------------
# v3 (28.09.2026, ART_DIRECTION v3 / R22): дерево художественного манекена без досок — клён и орех, обмотка, маска краски.
# Волокна вдоль V; 1 тайл = 0.5 м на кукле (uv_cylinder_along(..., scale=2)). Кольца — целое число на тайл (бесшовно по U).
# ----------------------------------------------------------------------------------------------------------------------
# 28.09 (интеграция v3): клён теплее и насыщеннее — под солнцем арены и холодным fill бледный клён читался как белый пластик,
# на R22 светлая кукла золотисто-медовая. Было: early (222,190,146), late (190,152,106), ray (234,208,168), dark (140,106,70).
MAPLE = dict(early=srgb(212, 170, 114), late=srgb(178, 132, 82), ray=srgb(226, 190, 138), dark=srgb(124, 88, 52))
WALNUT = dict(early=srgb(118, 80, 50), late=srgb(78, 50, 30), ray=srgb(138, 100, 68), dark=srgb(50, 30, 16))


def solid_wood_nodes(nb, pal, rings=36, contrast=0.35, arcs=0.4, figure=0.12, seed=0.0, pore=0.10, wave=1.0):
    """Токарное дерево без швов: годовые кольца поперёк U (растянуты вдоль V, у каждой линии своя лёгкая волна,
    слабые «соборные» дуги), сердцевинные лучи, поры, крупная тональная вариация и поперечные «фигурные» полосы."""
    u, v = nb.u, nb.v
    warp = nb.noise(2.0, 0.5, detail=2.0, rough=0.5, seed=seed + 1)             # общий медленный изгиб
    warp2 = nb.noise(9.0, 1.2, detail=2.0, rough=0.5, seed=seed + 2)            # своя волна у соседних линий
    warp3 = nb.noise(30.0, 4.0, detail=1.0, seed=seed + 12)                     # мелкая дрожь
    arc = nb.cos(nb.mad(v, TAU, nb.mul(u, 2.0)))
    r = nb.lin([(rings, u), (1.0 * wave, warp), (0.9 * wave, warp2), (0.25, warp3), (arcs * 1.2, arc)])
    t = nb.fract(r)
    wn = nb.noise(14.0, 1.5, detail=1.0, seed=seed + 3)                         # ширина линии меняется от линии к линии
    late = nb.sstep(t, nb.mad(wn, 0.30, 0.45), 0.93)
    gap = nb.noise(2.0, 4.0, detail=2.0, seed=seed + 9)
    gap2 = nb.noise(6.0, 1.0, detail=1.0, seed=seed + 15)
    late = nb.mul(late, nb.mul(nb.mad(gap, 0.9, 0.35), nb.mad(gap2, 0.8, 0.5)))    # линии местами гаснут, не «пинстрайп»
    fine = nb.noise(140.0, 5.0, detail=2.0, rough=0.6, seed=seed + 4)
    fine2 = nb.noise(400.0, 20.0, detail=1.0, seed=seed + 13)
    pores = nb.sstep(nb.noise(220.0, 12.0, detail=1.0, seed=seed + 5), 0.66, 0.74)
    rays = nb.mul(nb.sstep(nb.noise(70.0, 1.0, detail=1.0, seed=seed + 6), 0.60, 0.70), nb.sstep(nb.noise(5.0, 5.0, detail=1.0, seed=seed + 7), 0.45, 0.65))
    age = nb.noise(1.5, 1.5, detail=3.0, rough=0.5, seed=seed + 8)
    streak = nb.sstep(nb.noise(6.0, 0.6, detail=2.0, seed=seed + 14), 0.58, 0.75)   # широкие тёмные полосы (сердцевина)
    fig = nb.mad(nb.sin(nb.mad(v, TAU * 5.0, nb.mul(nb.noise(1.0, 1.0, detail=1.0, seed=seed + 10), 6.0))), 0.5, 0.5)
    fig = nb.mul(fig, nb.noise(2.0, 2.0, detail=1.0, seed=seed + 11))
    col = nb.mixc(pal['early'], pal['late'], nb.clamp01(nb.mul(late, contrast * 2.0)))
    col = nb.mixc(col, pal['late'], nb.mul(streak, contrast * 0.9))
    col = nb.mixc(col, pal['ray'], nb.mul(rays, 0.35))
    col = nb.scalec(col, nb.mad(fine, 0.14, 0.93))
    col = nb.scalec(col, nb.mad(fine2, 0.08, 0.96))
    col = nb.scalec(col, nb.mad(age, 0.22, 0.89))
    col = nb.scalec(col, nb.mad(fig, figure, 1.0 - figure * 0.5))
    col = nb.mixc(col, pal['dark'], nb.mul(pores, pore))
    height = nb.lin([(0.10, fine), (0.05, fine2), (-0.16, late), (-0.30, pores), (0.06, rays)], bias=0.55)
    rough = nb.clamp01(nb.lin([(0.10, late), (0.08, fine), (0.15, pores), (-0.12, fig)], bias=0.44))   # сатиновый лак
    return dict(color=col, rough=rough, height=height, bump=0.008)


def maple_light_nodes(nb, seed=0.0):
    """Бледный клён: мелкое прямое волокно, низкий контраст, лёгкий фигурный блеск."""
    return solid_wood_nodes(nb, MAPLE, rings=30, contrast=0.26, arcs=0.10, figure=0.16, seed=seed, pore=0.06, wave=0.8)


def walnut_dark_nodes(nb, seed=0.0):
    """Тёмный орех: насыщенно-коричневый, средний контраст колец, заметные дуги и поры."""
    return solid_wood_nodes(nb, WALNUT, rings=22, contrast=0.36, arcs=0.22, figure=0.08, seed=seed, pore=0.14, wave=1.1)


def cloth_wrap_nodes(nb, seed=3.0):
    """Обмотка: светлая нейтральная ткань (цвет даёт baseColorFactor = цвет игрока), плотное переплетение."""
    return fabric_nodes(nb, base=srgb(224, 216, 204), seed=seed, threads=48)


def paint_marks_nodes(nb, seed=0.0):
    """Маска мазков краски (RGBA): редкие узкие штрихи вдоль V (кистью по волокну) с рваными краями и каплями;
    цвет почти белый (умножается на цвет игрока), alpha — покрытие. Оболочки-декали Shirt на груди/плечах/бёдрах."""
    u, v = nb.u, nb.v
    s1 = nb.noise(30.0, 1.4, detail=2.0, rough=0.5, seed=seed + 1)          # полосы по U, длинные по V (мазок кистью)
    s2 = nb.noise(4.0, 1.6, detail=2.0, rough=0.5, seed=seed + 2)           # где вообще есть мазки
    s3 = nb.noise(90.0, 90.0, detail=1.0, seed=seed + 3)                    # рваная кромка
    bristle = nb.noise(160.0, 3.0, detail=1.0, seed=seed + 7)               # щетина: продольные просветы
    stroke = nb.mul(nb.sstep(s1, 0.505, 0.56), nb.sstep(s2, 0.47, 0.58))
    stroke = nb.sstep(nb.lin([(1.0, stroke), (0.30, s3), (0.25, bristle)], bias=-0.30), 0.30, 0.55)
    drip = nb.mul(nb.sstep(nb.noise(70.0, 0.8, detail=1.0, seed=seed + 4), 0.74, 0.77), nb.sstep(s2, 0.52, 0.62))
    alpha = nb.clamp01(nb.lin([(1.0, stroke), (0.9, drip)]))
    thin = nb.noise(14.0, 14.0, detail=2.0, seed=seed + 5)
    alpha = nb.mul(alpha, nb.mad(thin, 0.35, 0.72))
    col = nb.scalec(srgb(240, 236, 232), nb.mad(nb.noise(7.0, 7.0, detail=2.0, seed=seed + 6), 0.18, 0.88))
    rough = nb.lerp(0.75, 0.45, alpha)
    height = nb.mul(alpha, 0.6)
    return dict(color=col, rough=rough, height=height, bump=0.004, alpha=alpha)


MATERIALS.update({
    'maple_light': (lambda nb: maple_light_nodes(nb, seed=0.0), 2048),
    'walnut_dark': (lambda nb: walnut_dark_nodes(nb, seed=4.0), 2048),
    'cloth_wrap': (lambda nb: cloth_wrap_nodes(nb, seed=3.0), 1024),
    'paint_marks': (lambda nb: paint_marks_nodes(nb, seed=0.0), 1024),
})

_bake_material_v2 = bake_material


def bake_material(name, build, size, samples=4):
    """v3: как bake_material, но если у материала есть канал alpha — albedo.png пишется RGBA (маска в alpha).
    Старые материалы идут через прежний путь без изменений."""
    if bpy is None:
        raise RuntimeError('нужен Blender')
    probe_mat = bpy.data.materials.new('__probe')
    probe_mat.use_nodes = True
    probe_mat.node_tree.nodes.clear()
    has_alpha = build(NB(probe_mat.node_tree)).get('alpha') is not None
    bpy.data.materials.remove(probe_mat)
    if not has_alpha:
        return _bake_material_v2(name, build, size, samples)
    t0 = time.time()
    out_dir = os.path.join(PBR, name)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = _setup_cycles(samples)
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    mat = bpy.data.materials.new('Bake_' + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    plane.data.materials.append(mat)
    nb = NB(nt)
    ch = build(nb)
    out = nb.new('ShaderNodeOutputMaterial')
    emit = nb.new('ShaderNodeEmission')
    tex = nb.new('ShaderNodeTexImage')
    nt.nodes.active = tex
    nt.links.new(emit.outputs['Emission'], out.inputs['Surface'])
    bpy.ops.object.select_all(action='DESELECT')
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane

    def bake(source):
        img = bpy.data.images.new('__bake', size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = 'Non-Color'
        tex.image = img
        for l in list(emit.inputs['Color'].links):
            nt.links.remove(l)
        nb.plug(emit.inputs['Color'], source)
        bpy.ops.object.bake(type='EMIT')
        arr = _read_float(img)
        bpy.data.images.remove(img)
        return arr

    a8 = _linear_to_srgb8(bake(ch['color']))
    al = bake(ch['alpha'])
    a8[..., 3] = np.clip(np.rint(np.clip(al[..., 0], 0, 1) * 255.0), 0, 255).astype(np.uint8)
    save_rgba8(os.path.join(out_dir, 'albedo.png'), a8, alpha=True)
    rough = bake(ch['rough'])
    r8 = np.clip(np.rint(np.clip(rough, 0, 1) * 255.0), 0, 255).astype(np.uint8)
    r8[..., 1] = r8[..., 0]
    r8[..., 2] = r8[..., 0]
    r8[..., 3] = 255
    save_rgba8(os.path.join(out_dir, 'roughness.png'), r8)
    print('baked %-14s %4d² RGBA in %5.1fs  coverage %.0f%%' % (name, size, time.time() - t0, 100.0 * (a8[..., 3] > 96).mean()))


# ----------------------------------------------------------------------------------------------------------------------
# v3.1 (28.09.2026): половая доска для полов/настилов арены (R22: пол мастерской). Отдельно от wood/wood_dark, те не трогаем.
# ----------------------------------------------------------------------------------------------------------------------
PLANK = dict(early=srgb(152, 102, 56), late=srgb(96, 56, 26), ray=srgb(172, 126, 80), dark=srgb(46, 26, 12), seam=srgb(26, 15, 8))


def _plank_grain(nb, pal, lines=20, seed=0.0):
    """Волокно одной доски в её координатах (u поперёк 0..1, v вдоль): тонкие мягкие линии (треугольный профиль от
    середины периода), у каждой линии своя толщина, плотность линий меняется поперёк доски (сгущения/разрежения),
    линии местами гаснут, широкие мягкие тёмные полосы вдоль, мелкий шум, поры. Без дуг и сучков."""
    u, v = nb.u, nb.v
    warp = nb.noise(2.0, 0.5, detail=2.0, rough=0.5, seed=seed + 1)         # медленный изгиб
    warp2 = nb.noise(9.0, 1.2, detail=2.0, rough=0.5, seed=seed + 2)        # соседние линии гуляют по-разному
    dens = nb.noise(5.0, 0.25, detail=1.0, seed=seed + 3)                   # плотность линий поперёк (почти константа вдоль)
    r = nb.lin([(lines, u), (0.6, warp), (0.5, warp2), (3.5, dens)])
    d = nb.absv(nb.sub(nb.fract(r), 0.5))                                   # 0 — центр линии, 0.5 — между линиями
    wn = nb.noise(40.0, 0.6, detail=1.0, seed=seed + 4)                     # толщина своя у каждой линии
    hw = nb.mad(wn, 0.10, 0.04)
    line = nb.sstep(d, hw, nb.mul(hw, 0.4))
    fade = nb.mul(nb.mad(nb.noise(3.0, 3.0, detail=2.0, seed=seed + 5), 0.9, 0.3),
                  nb.mad(nb.noise(8.0, 0.8, detail=1.0, seed=seed + 6), 0.8, 0.45))
    line = nb.mul(line, fade)
    streak = nb.sstep(nb.noise(4.0, 0.4, detail=2.0, seed=seed + 7), 0.55, 0.78)   # широкие мягкие полосы вдоль
    fine = nb.noise(140.0, 5.0, detail=2.0, rough=0.6, seed=seed + 8)
    fine2 = nb.noise(400.0, 20.0, detail=1.0, seed=seed + 9)
    pores = nb.sstep(nb.noise(220.0, 12.0, detail=1.0, seed=seed + 10), 0.66, 0.74)
    age = nb.noise(1.5, 1.5, detail=3.0, rough=0.5, seed=seed + 11)
    col = nb.mixc(pal['early'], pal['late'], nb.clamp01(nb.mul(line, 0.70)))
    col = nb.mixc(col, pal['late'], nb.mul(streak, 0.30))
    col = nb.scalec(col, nb.mad(fine, 0.14, 0.93))
    col = nb.scalec(col, nb.mad(fine2, 0.08, 0.96))
    col = nb.scalec(col, nb.mad(age, 0.22, 0.89))
    col = nb.mixc(col, pal['dark'], nb.mul(pores, 0.10))
    height = nb.lin([(0.10, fine), (0.05, fine2), (-0.14, line), (-0.30, pores)], bias=0.55)
    rough = nb.clamp01(nb.lin([(0.10, line), (0.08, fine), (0.15, pores), (0.05, streak)], bias=0.58))
    return dict(color=col, rough=rough, height=height)


def wood_plank_nodes(nb, planks=4, lines=20, pal=PLANK, seed=21.0):
    """Половая доска: `planks` досок поперёк U на тайл (1 м → доска 25 см), волокно вдоль V — узкое ПРЯМОЕ (см. _plank_grain),
    у каждой доски свой сдвиг фазы/рисунка и свой тон; тонкие тёмные швы (≈3 мм) со скруглённой кромкой; потёртые светлые
    пятна и пыль по всему тайлу. Тон средне-тёплый — между wood и wood_dark."""
    u, v = nb.u, nb.v
    pu = nb.mul(u, planks)
    pid = nb.floor(pu)
    ul = nb.fract(pu)
    h1 = nb.white(pid, 1.0, seed)
    h2 = nb.white(pid, 2.0, seed)
    h3 = nb.white(pid, 3.0, seed)
    # дерево доски в её координатах: nb.u/nb.v временно подменяем (_plank_grain и noise() читают их)
    nb.u = nb.add(ul, nb.mul(h1, 0.37))          # фаза линий своя у каждой доски
    nb.v = nb.add(v, nb.mul(h2, 5.0))            # рисунок вдоль доски свой (тор периодичен по v, сдвиг любой)
    try:
        w = _plank_grain(nb, pal, lines=lines, seed=seed + 7.0)
    finally:
        nb.u, nb.v = u, v
    wear = nb.sstep(nb.noise(2.5, 2.5, detail=4.0, rough=0.55, seed=seed + 9), 0.56, 0.74)   # потёртые светлые пятна (по тайлу)
    dust = nb.sstep(nb.noise(5.0, 5.0, detail=3.0, rough=0.5, seed=seed + 10), 0.60, 0.80)   # пыль/грязь
    e = nb.absv(nb.sub(ul, 0.5))
    seamm = nb.sstep(e, 0.482, 0.496)
    bev = nb.sstep(e, 0.43, 0.482)
    col = nb.scalec(w['color'], nb.mad(h1, 0.22, 0.88))
    col = nb.scalec(col, nb.mad(h3, 0.10, 0.95))
    col = nb.mixc(col, pal['ray'], nb.mul(wear, 0.30))
    col = nb.mixc(col, pal['dark'], nb.mul(dust, 0.18))
    col = nb.scalec(col, nb.sub(1.0, nb.mul(bev, 0.18)))
    col = nb.mixc(col, pal['seam'], seamm)
    height = nb.lin([(1.0, w['height']), (-0.35, bev), (-0.55, seamm)])
    rough = nb.clamp01(nb.lin([(1.0, w['rough']), (0.20, seamm), (0.12, dust), (-0.14, wear)]))
    return dict(color=col, rough=rough, height=height, bump=0.012, seam=seamm)


MATERIALS.update({
    'wood_plank': (lambda nb: wood_plank_nodes(nb, planks=4, seed=21.0), 2048),
})


# ----------------------------------------------------------------------------------------------------------------------
# THE SCRAP (28.09.2026): биом 1 «Свалка», листы docs/refs/biomes/01-scrap (sheet-01…05, kit-01/02). Ржавое клёпаное
# железо, облупленная красная краска по ржавчине, старые грязные доски, грязь/пыль земли, потёртая латунь.
# Клёпки, вмятины, гофра — геометрия, в текстурах их нет. Свет на листах закатный — в альбедо его не запекаем.
# У rust_metal / rust_painted_red / brass_worn канал metal — КАРТА (сокет, не константа): печётся в metallic.png
# (bake_material v4 ниже). Подтёки идут вниз по V: при uv_box(along='Z') / uv_cylinder_along V = мировой верх.
# Превью: Blender -b --python textures.py -- --scrap-preview  → docs/plan-demo/img/scrap-materials-v1.png
# ----------------------------------------------------------------------------------------------------------------------
def _torus_group():
    """Нод-группа «тор» (U, V, FU, FV, Seed) → (Vector, W): те же формулы, что NB.torus, но одним узлом в материале.
    Blender пересчитывает дерево на каждую новую связь, сборка растёт ~квадратично: граф ржавчины в 1500 нод строился
    8 минут, с группой — секунды. Группа живёт в bpy.data и пересоздаётся после read_factory_settings."""
    g = bpy.data.node_groups.get('ScrapTorus')
    if g is not None:
        return g
    g = bpy.data.node_groups.new('ScrapTorus', 'ShaderNodeTree')
    for nm in ('U', 'V', 'FU', 'FV', 'Seed'):
        g.interface.new_socket(nm, in_out='INPUT', socket_type='NodeSocketFloat')
    g.interface.new_socket('Vector', in_out='OUTPUT', socket_type='NodeSocketVector')
    g.interface.new_socket('W', in_out='OUTPUT', socket_type='NodeSocketFloat')
    gi = g.nodes.new('NodeGroupInput')
    go = g.nodes.new('NodeGroupOutput')
    nb = NB.__new__(NB)                     # без UV-ноды: u, v приходят входами группы
    nb.nt, nb.count = g, 0
    ru = nb.mul(gi.outputs['FU'], 1.0 / TAU)
    rv = nb.mul(gi.outputs['FV'], 1.0 / TAU)
    au = nb.mul(gi.outputs['U'], TAU)
    av = nb.mul(gi.outputs['V'], TAU)
    x = nb.mad(nb.cos(au), ru, nb.mul(gi.outputs['Seed'], 1.73))
    y = nb.mul(nb.sin(au), ru)
    z = nb.mad(nb.cos(av), rv, nb.mul(gi.outputs['Seed'], 0.91))
    w = nb.mul(nb.sin(av), rv)
    comb = nb.new('ShaderNodeCombineXYZ')
    for i, c in enumerate((x, y, z)):
        g.links.new(c, comb.inputs[i])
    g.links.new(comb.outputs[0], go.inputs['Vector'])
    g.links.new(w, go.inputs['W'])
    return g


def _tvec(nb, fu, fv, seed=0.0, u=None, v=None):
    node = nb.new('ShaderNodeGroup')
    node.node_tree = _torus_group()
    nb.plug(node.inputs['U'], nb.u if u is None else u)
    nb.plug(node.inputs['V'], nb.v if v is None else v)
    nb.plug(node.inputs['FU'], fu)
    nb.plug(node.inputs['FV'], fv)
    nb.plug(node.inputs['Seed'], seed)
    return node.outputs['Vector'], node.outputs['W']


def _gn(nb, fu, fv, detail=2.0, rough=0.5, seed=0.0, u=None, v=None):
    """= nb.noise(...) (бесшовный 4D-шум на торе), но через группу ScrapTorus: 2 узла вместо 13."""
    vec, w = _tvec(nb, fu, fv, seed, u, v)
    node = nb.new('ShaderNodeTexNoise', noise_dimensions='4D')
    node.inputs['Scale'].default_value = 1.0
    node.inputs['Detail'].default_value = detail
    node.inputs['Roughness'].default_value = rough
    node.inputs['Distortion'].default_value = 0.0
    nb.plug(node.inputs['Vector'], vec)
    nb.plug(node.inputs['W'], w)
    return node.outputs['Fac']


def _gv(nb, fu, fv, feature='F1', randomness=1.0, seed=0.0, u=None, v=None):
    """= nb.voronoi(...) через группу ScrapTorus (возвращает ноду: Distance, Color, Position)."""
    vec, w = _tvec(nb, fu, fv, seed, u, v)
    node = nb.new('ShaderNodeTexVoronoi', voronoi_dimensions='4D', feature=feature)
    node.inputs['Scale'].default_value = 1.0
    node.inputs['Randomness'].default_value = randomness
    nb.plug(node.inputs['Vector'], vec)
    nb.plug(node.inputs['W'], w)
    return node


SCRAP_IRON = dict(base=srgb(64, 62, 62), scale=srgb(40, 43, 50), bright=srgb(136, 134, 130), stain=srgb(88, 58, 40),
                  film=srgb(112, 62, 34))
RUST = dict(dark=srgb(62, 31, 18), mid=srgb(122, 58, 26), light=srgb(164, 86, 38), pale=srgb(186, 124, 72), pit=srgb(22, 15, 11),
            drip=srgb(104, 52, 26))


def _drip_source(nb, field, offsets=(0.015, 0.045, 0.09, 0.15, 0.23), falloff=0.78):
    """Подтёки вниз по V: max_k w_k·field(v + d_k) — точка «видит» источник выше себя, вес падает с расстоянием.
    field(vv) строит маску источника 0..1 в точке (u, vv); сдвиг по v на торе остаётся бесшовным."""
    acc, w = None, 1.0
    for d in offsets:
        s = field(nb.add(nb.v, d))
        if w != 1.0:
            s = nb.mul(s, w)
        acc = s if acc is None else nb.maxv(acc, s)
        w *= falloff
    return acc


def _scratches(nb, seed, freq=28.0, width=0.012, seg=7.0, keep=0.60,
               dirs=((1, 0), (0, 1), (1, 1), (1, -1), (2, 1), (1, -2))):
    """Тонкие прямые царапины разных направлений: изолинии n = 0.5 анизотропного шума (быстрый поперёк, почти
    постоянный вдоль) в повёрнутых координатах s = a·u + b·v, t = −b·u + a·v — при целых a, b тор остаётся бесшовным;
    порезаны маской на короткие отрезки, яркость отрезков разная. → маска 0..1."""
    acc = None
    for k, (a, b) in enumerate(dirs):
        L = math.hypot(a, b)
        s = nb.lin([(float(a), nb.u), (float(b), nb.v)])
        t = nb.lin([(float(-b), nb.u), (float(a), nb.v)])
        n = _gn(nb, freq * L, 0.6 * L, detail=1.0, seed=seed + 3.1 * k, u=s, v=t)
        line = nb.sstep(nb.absv(nb.sub(n, 0.5)), width, 0.0)
        cut = nb.sstep(_gn(nb, seg, seg, detail=2.0, seed=seed + 3.1 * k + 1.3), keep, keep + 0.04)
        fade = nb.mad(_gn(nb, seg * 3.0, seg * 3.0, detail=1.0, seed=seed + 3.1 * k + 2.2), 1.0, 0.1)
        m = nb.mul(nb.mul(line, cut), fade)
        acc = m if acc is None else nb.maxv(acc, m)
    return nb.clamp01(acc)


def _rust_field(nb, seed, vv=None, detail=6.0):
    """Поле ржавчины (~0.5 ± 0.1): крупные пятна fBm + средняя рябь. Одно поле — и для пятен, и для источников подтёков."""
    b1 = _gn(nb, 2.2, 2.2, detail=detail, rough=0.62, seed=seed + 2, v=vv)
    b2 = _gn(nb, 7.0, 7.0, detail=3.0, rough=0.5, seed=seed + 3, v=vv)
    return nb.lin([(1.0, b1), (0.25, b2)], bias=-0.125)


def rust_metal_nodes(nb, seed=0.0, thr=0.52):
    """Клёпаный лист железа (№034, кит K01–K22): тёмное железо с прокатными полосами вдоль U и сине-чёрной окалиной
    пятнами; вокруг ржавых пятен — рыжевато-бурый налёт (плёнка) с рваными краями; сами пятна с рваной кромкой, внутри
    слоистые: тёмно-бурые у кромки, оранжевые, светлые мелкие чешуйки в глубине (ячейки Voronoi: свой тон, подъём,
    трещинки между ними); подтёки вниз по V из-под пятен; питтинг (гуще в ржавчине и налёте) и редкие каверны;
    прямые царапины по чистому металлу. thr — порог поля ржавчины (меньше — ржавее).
    Металличность: железо 0.9, налёт 0.5, подтёк 0.35, ржавчина 0.04–0.14, царапина 1. Шероховатость 0.55…0.95."""
    rf = _rust_field(nb, seed)
    rag = _gn(nb, 40.0, 40.0, detail=3.0, rough=0.6, seed=seed + 4)
    patch = nb.sstep(nb.lin([(1.0, rf), (0.20, rag)], bias=-0.10), thr, thr + 0.02)     # рваная кромка пятна
    spn = _gn(nb, 26.0, 26.0, detail=2.0, rough=0.5, seed=seed + 5)
    spots = nb.sstep(nb.lin([(1.0, spn), (0.5, rf)], bias=-0.25), 0.70, 0.73)          # крапины, гуще у пятен
    rustm = nb.maxv(patch, spots)
    rd = nb.sstep(rf, thr, thr + 0.14)                                                  # «глубина» ржавчины
    filmn = _gn(nb, 18.0, 18.0, detail=3.0, rough=0.6, seed=seed + 22)
    film = nb.mul(nb.sstep(nb.lin([(1.0, rf), (0.30, filmn)], bias=-0.15), thr - 0.09, thr - 0.01), nb.sub(1.0, rustm))
    # чешуйки ржавчины: общий рисунок ячеек для F1 (тон/подъём) и расстояния до ребра (трещинки)
    fl = _gv(nb, 44.0, 44.0, seed=seed + 6)
    fe = _gv(nb, 44.0, 44.0, feature='DISTANCE_TO_EDGE', seed=seed + 6)
    fcell = nb.sepc(fl.outputs['Color'])[0]
    deep = nb.sstep(rd, 0.35, 0.9)
    fcrack = nb.mul(nb.sstep(fe.outputs['Distance'], 0.035, 0.0), deep)
    rt = _gn(nb, 9.0, 9.0, detail=4.0, rough=0.55, seed=seed + 7)
    rt2 = _gn(nb, 3.0, 3.0, detail=3.0, rough=0.5, seed=seed + 23)
    rg = _gn(nb, 90.0, 90.0, detail=2.0, rough=0.6, seed=seed + 8)
    rg2 = _gn(nb, 280.0, 280.0, detail=2.0, rough=0.6, seed=seed + 25)             # микрозерно (крупный план)
    tone = nb.lin([(1.0, rt), (0.6, rt2), (0.14, nb.mul(fcell, deep)), (0.30, rd)], bias=-0.48)
    rcol = nb.ramp(tone, [(0.15, RUST['dark']), (0.40, RUST['mid']), (0.62, RUST['light']), (0.86, RUST['pale'])])
    rcol = nb.scalec(rcol, nb.mad(rg, 0.36, 0.82))
    rcol = nb.scalec(rcol, nb.mad(rg2, 0.30, 0.85))
    rcol = nb.scalec(rcol, nb.sub(1.0, nb.mul(fcrack, 0.45)))
    rcol = nb.mixc(rcol, RUST['dark'], nb.mul(nb.sub(1.0, rd), 0.5))                   # тонкая ржавчина у кромки — бурая
    # металл
    mot = _gn(nb, 3.0, 3.0, detail=4.0, rough=0.55, seed=seed + 9)
    mot2 = _gn(nb, 11.0, 11.0, detail=3.0, rough=0.55, seed=seed + 24)
    roll = _gn(nb, 1.2, 70.0, detail=1.0, seed=seed + 10)                               # прокатные полосы вдоль U
    scl = nb.sstep(_gn(nb, 5.0, 5.0, detail=3.0, rough=0.5, seed=seed + 11), 0.55, 0.68)  # окалина
    metal = nb.mixc(SCRAP_IRON['base'], SCRAP_IRON['scale'], nb.mul(scl, 0.7))
    metal = nb.scalec(metal, nb.mad(mot, 0.55, 0.74))
    metal = nb.scalec(metal, nb.mad(mot2, 0.20, 0.90))
    metal = nb.scalec(metal, nb.mad(roll, 0.10, 0.95))
    metal = nb.mixc(metal, nb.mixc(SCRAP_IRON['stain'], SCRAP_IRON['film'], filmn), nb.mul(film, 0.6))
    # подтёки: вертикальные струи под пятнами, гаснут книзу
    above = _drip_source(nb, lambda vv: nb.sstep(_rust_field(nb, seed, vv, detail=3.0), thr - 0.03, thr + 0.08))
    sl = _gn(nb, 56.0, 1.0, detail=2.0, rough=0.5, seed=seed + 12)
    sl2 = _gn(nb, 12.0, 0.5, detail=1.0, seed=seed + 13)
    streak = nb.mul(nb.sstep(sl, 0.45, 0.58), nb.sstep(sl2, 0.30, 0.55))
    drip = nb.mul(nb.mul(streak, above), nb.sub(1.0, rustm))
    metal = nb.mixc(metal, RUST['drip'], nb.mul(drip, 0.9))
    # питтинг и каверны
    pv = _gv(nb, 80.0, 80.0, seed=seed + 14)
    pit = nb.mul(nb.sstep(pv.outputs['Distance'], 0.26, 0.08), nb.gt(nb.sepc(pv.outputs['Color'])[0], 0.5))
    pit = nb.mul(pit, nb.mad(nb.maxv(film, rd), 0.8, 0.2))
    cv = _gv(nb, 28.0, 28.0, seed=seed + 15)
    crater = nb.mul(nb.mul(nb.sstep(cv.outputs['Distance'], 0.30, 0.12), nb.gt(nb.sepc(cv.outputs['Color'])[0], 0.82)), rustm)
    pit = nb.maxv(pit, crater)
    scratch = nb.mul(_scratches(nb, seed + 30.0, keep=0.67, dirs=((1, 0), (1, 1), (1, -1), (2, 1))), nb.sub(1.0, nb.mul(rustm, 0.85)))
    # сборка
    col = nb.mixc(metal, rcol, rustm)
    col = nb.mixc(col, SCRAP_IRON['bright'], nb.mul(scratch, 0.6))
    col = nb.mixc(col, RUST['pit'], nb.mul(pit, 0.75))
    height = nb.lin([(0.03, roll), (0.05, mot), (0.10, rustm), (0.16, nb.mul(deep, fcell)), (-0.18, fcrack),
                     (0.08, nb.mul(rg, rustm)), (0.05, nb.mul(rg2, rustm)), (-0.05, film), (-0.40, pit), (-0.25, scratch)], bias=0.5)
    rm = nb.lin([(0.10, mot), (0.05, roll), (0.06, scl)], bias=0.53)
    rm = nb.lerp(rm, 0.76, film)
    rm = nb.lerp(rm, 0.82, drip)
    rr = nb.lin([(0.10, rg), (0.05, fcell)], bias=0.82)
    rough = nb.lerp(rm, rr, rustm)
    rough = nb.lin([(1.0, rough), (0.06, pit), (-0.06, scratch)])
    rough = nb.minv(nb.maxv(rough, 0.55), 0.95)
    mm = nb.lerp(0.9, 0.78, scl)
    mm = nb.lerp(mm, 0.5, film)
    mm = nb.lerp(mm, 0.35, drip)
    metal_map = nb.lerp(mm, nb.lerp(0.14, 0.04, rd), rustm)
    metal_map = nb.lerp(metal_map, 1.0, scratch)
    metal_map = nb.lerp(metal_map, 0.2, pit)
    return dict(color=col, rough=rough, height=height, bump=0.012, metal=metal_map, rust=rustm, film=film)


PAINT_SCRAP_RED = srgb(146, 36, 28)


def _chip_field(nb, seed, vv=None, detail=6.0):
    """Поле сколов краски (~0.5 ± 0.08): крупные острова + средняя рябь; им же ищутся сколы выше точки для подтёков."""
    m1 = _gn(nb, 3.0, 3.0, detail=detail, rough=0.62, seed=seed + 1, v=vv)
    m2 = _gn(nb, 12.0, 12.0, detail=3.0, rough=0.5, seed=seed + 2, v=vv)
    return nb.lin([(1.0, m1), (0.18, m2)], bias=-0.09)


def _pbr_layer(nb, name, du=0.0, dv=0.0):
    """Уже запечённый набор assets/textures/pbr/<name>/ как слой графа (REPEAT, UV со сдвигом du/dv — бесшовно):
    → dict(color, rough, metal, normal_rgb). Нужен там, где полный процедурный граф основы не лезет в стек SVM Cycles
    («out of SVM stack space … too big» → чёрный бейк): краска поверх ржавчины."""
    d = os.path.join(PBR, name)
    if not os.path.exists(os.path.join(d, 'albedo.png')):
        raise FileNotFoundError('сначала запеки ' + name + ' (textures.py -- ' + name + ')')
    comb = nb.new('ShaderNodeCombineXYZ')
    nb.plug(comb.inputs[0], nb.add(nb.u, du))
    nb.plug(comb.inputs[1], nb.add(nb.v, dv))

    def img(ch, non_color):
        p = os.path.join(d, ch + '.png')
        if not os.path.exists(p):
            return None
        node = nb.new('ShaderNodeTexImage')
        im = bpy.data.images.load(p, check_existing=True)
        im.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
        node.image = im
        node.extension = 'REPEAT'
        node.interpolation = 'Linear'
        nb.nt.links.new(comb.outputs[0], node.inputs['Vector'])
        return node.outputs['Color']

    out = dict(color=img('albedo', False), rough=nb.sepc(img('roughness', True))[0])
    met = img('metallic', True)
    out['metal'] = nb.sepc(met)[0] if met is not None else 0.0
    out['normal_rgb'] = img('normal', True)        # сырой RGB карты нормалей: _bake_scrap смешивает его с рельефом
    return out


def rust_painted_nodes(nb, paint=PAINT_SCRAP_RED, seed=0.0, keep=0.43, base='rust_metal'):
    """Облупленная красная краска по ржавому железу (бочка №026, транспортный ящик №024): жёсткий порог поля сколов,
    в сколах — запечённый rust_metal (слой со сдвигом UV, рисунок не совпадает с листом железа; его нормаль
    смешивается с рельефом краски), у кромки скола ржавчина темнее (подплёночная коррозия), кромка самой краски темнее и чуть
    приподнята; ниже сколов по краске — рыжие подтёки; выгоревшие светлые пятна, тёмные дождевые потёки вдоль V,
    грязь; тонкие прямые царапины сквозь краску до светлого металла. keep — порог поля: больше — сколов больше.
    Краска: metal 0, rough 0.46–0.8. Печь после rust_metal (порядок MATERIALS это соблюдает)."""
    r = _pbr_layer(nb, base, 0.37, 0.61)
    m3 = _gn(nb, 48.0, 48.0, detail=2.0, rough=0.5, seed=seed + 3)
    m = nb.lin([(1.0, _chip_field(nb, seed)), (0.07, m3)], bias=-0.035)
    sp = _gn(nb, 40.0, 40.0, detail=2.0, rough=0.5, seed=seed + 15)         # мелкие сколы-крапины по всей краске
    m = nb.sub(m, nb.mul(nb.sstep(sp, 0.70, 0.74), 0.2))
    pm = nb.sstep(m, keep, keep + 0.008)                                   # 1 — краска держится
    lip = nb.mul(pm, nb.sstep(m, keep + 0.04, keep + 0.008))               # кромка краски у скола
    ring = nb.mul(nb.sub(1.0, pm), nb.sstep(m, keep - 0.06, keep))         # ржавчина у кромки скола
    scratch = nb.mul(_scratches(nb, seed + 30.0, freq=22.0, width=0.010, seg=6.0, keep=0.70, dirs=((1, 0), (1, 1), (1, -1), (2, -1))), pm)
    above = _drip_source(nb, lambda vv: nb.sstep(_chip_field(nb, seed, vv, detail=3.0), keep + 0.03, keep - 0.04),
                         offsets=(0.02, 0.06, 0.11, 0.17, 0.24), falloff=0.75)
    streak = nb.mul(nb.sstep(_gn(nb, 50.0, 1.0, detail=2.0, seed=seed + 7), 0.46, 0.60),
                    nb.sstep(_gn(nb, 14.0, 0.5, detail=1.0, seed=seed + 8), 0.28, 0.55))
    bleed = nb.mul(nb.mul(streak, above), pm)
    var = _gn(nb, 6.0, 6.0, detail=3.0, rough=0.5, seed=seed + 9)
    fade = nb.sstep(_gn(nb, 1.8, 1.8, detail=4.0, rough=0.55, seed=seed + 10), 0.48, 0.70)
    grime = _gn(nb, 3.0, 3.0, detail=4.0, rough=0.55, seed=seed + 11)
    fine = _gn(nb, 120.0, 120.0, detail=2.0, rough=0.6, seed=seed + 12)
    rain = nb.mul(nb.sstep(_gn(nb, 34.0, 0.8, detail=2.0, seed=seed + 13), 0.52, 0.68),
                  nb.sstep(_gn(nb, 2.0, 2.0, detail=2.0, seed=seed + 14), 0.40, 0.65))   # тёмные дождевые потёки
    pc = nb.scalec(paint, nb.mad(var, 0.34, 0.83))
    pc = nb.mixc(pc, srgb(172, 88, 70), nb.mul(fade, 0.45))                # выгорела: светлее, в оранжево-розовый
    pc = nb.scalec(pc, nb.mad(grime, 0.44, 0.74))
    pc = nb.scalec(pc, nb.mad(fine, 0.12, 0.94))
    pc = nb.scalec(pc, nb.sub(1.0, nb.mul(rain, 0.28)))
    pc = nb.mixc(pc, srgb(108, 50, 26), nb.mul(bleed, 0.8))
    pc = nb.scalec(pc, nb.sub(1.0, nb.mul(lip, 0.40)))
    under = nb.scalec(r['color'], nb.sub(1.0, nb.mul(ring, 0.5)))
    col = nb.mixc(under, pc, pm)
    col = nb.mixc(col, SCRAP_IRON['bright'], nb.mul(scratch, 0.7))
    height = nb.lin([(0.50, pm), (0.12, lip), (0.03, nb.mul(fine, pm)), (-0.25, scratch)], bias=0.08)
    prough = nb.lin([(0.14, var), (0.12, grime), (0.10, fade), (0.10, bleed), (0.06, rain)], bias=0.46)
    rough = nb.lerp(r['rough'], prough, pm)
    rough = nb.lerp(rough, 0.5, scratch)
    metal = nb.lerp(r['metal'], 0.0, pm)
    metal = nb.lerp(metal, 0.95, scratch)
    return dict(color=col, rough=rough, height=height, bump=0.012, metal=metal, normal_rgb=r['normal_rgb'])


SCRAP_PLANK = dict(early=srgb(134, 96, 62), late=srgb(88, 61, 39), bleach=srgb(148, 134, 116), grey=srgb(116, 106, 96),
                   dirt=srgb(38, 28, 20), crack=srgb(22, 16, 11), fresh=srgb(164, 122, 80), seam=srgb(16, 12, 9))


def _scrap_grain(nb, lines=24, seed=0.0):
    """Волокно старой доски в её координатах (nb.u поперёк 0..1, nb.v вдоль) — как _plank_grain (линии своей толщины,
    сгущения, гаснущие участки), плюс лёгкая волна по длине, второй слой тонких линий и продольные трещины;
    возвращает маски (цвет собирает scrap_wood_nodes)."""
    u, v = nb.u, nb.v
    warp = _gn(nb, 2.0, 0.5, detail=2.0, rough=0.5, seed=seed + 1)
    warp2 = _gn(nb, 9.0, 1.2, detail=2.0, rough=0.5, seed=seed + 2)
    dens = _gn(nb, 5.0, 0.25, detail=1.0, seed=seed + 3)
    arc = nb.cos(nb.mad(v, TAU, nb.mul(u, 1.5)))
    r = nb.lin([(lines, u), (0.8, warp), (0.6, warp2), (3.5, dens), (0.7, arc)])
    d = nb.absv(nb.sub(nb.fract(r), 0.5))
    hw = nb.mad(_gn(nb, 40.0, 0.6, detail=1.0, seed=seed + 4), 0.10, 0.04)
    line = nb.sstep(d, hw, nb.mul(hw, 0.35))
    fade = nb.mul(nb.mad(_gn(nb, 3.0, 3.0, detail=2.0, seed=seed + 5), 0.9, 0.35),
                  nb.mad(_gn(nb, 8.0, 0.8, detail=1.0, seed=seed + 6), 0.8, 0.5))
    line = nb.clamp01(nb.mul(line, fade))
    d2 = nb.absv(nb.sub(nb.fract(nb.mad(r, 2.7, 0.33)), 0.5))                      # тонкие промежуточные линии
    line2 = nb.mul(nb.sstep(d2, 0.10, 0.03), _gn(nb, 6.0, 0.7, detail=1.0, seed=seed + 13))
    streak = nb.sstep(_gn(nb, 4.0, 0.4, detail=2.0, seed=seed + 7), 0.55, 0.78)
    band = nb.sstep(_gn(nb, 10.0, 0.6, detail=2.0, seed=seed + 14), 0.50, 0.72)   # тёмные полосы средней ширины
    fine = _gn(nb, 140.0, 5.0, detail=2.0, rough=0.6, seed=seed + 8)
    fine2 = _gn(nb, 400.0, 20.0, detail=1.0, seed=seed + 9)
    pores = nb.sstep(_gn(nb, 220.0, 12.0, detail=1.0, seed=seed + 10), 0.64, 0.72)
    cr1 = _gn(nb, 12.0, 0.9, detail=2.0, rough=0.5, seed=seed + 11)
    cr2 = _gn(nb, 1.0, 1.2, detail=2.0, rough=0.5, seed=seed + 12)
    crack = nb.mul(nb.sstep(cr1, 0.70, 0.74), nb.sstep(cr2, 0.50, 0.62))
    return dict(line=line, line2=line2, streak=streak, band=band, fine=fine, fine2=fine2, pores=pores, crack=crack)


def scrap_wood_nodes(nb, planks=4, lines=24, pal=SCRAP_PLANK, seed=31.0):
    """Старые грязные доски свалки (ящики №021/016, стены №053, поддоны): оси и швы как у wood_plank (`planks` досок
    поперёк U, волокно вдоль V, шов ≈3 мм со скруглённой кромкой), но палитра приглушённая; обветренное рельефное
    волокно (поздняя древесина выступает, в бороздках грязь), выгоревшие серо-бежевые пятна, посеревшие доски, водяные
    разводы с тёмной каймой, грязь у швов и брызги грязи, продольные трещины, мелкие сучки, отверстия, прямые царапины
    (свежие — светлее, старые — тёмные). Без металличности; шероховатость 0.78–0.95."""
    u, v = nb.u, nb.v
    pu = nb.mul(u, planks)
    pid = nb.floor(pu)
    ul = nb.fract(pu)
    h1 = nb.white(pid, 1.0, seed)
    h2 = nb.white(pid, 2.0, seed)
    h3 = nb.white(pid, 3.0, seed)
    h4 = nb.white(pid, 4.0, seed)
    nb.u = nb.add(ul, nb.mul(h1, 0.37))           # фаза линий своя у каждой доски
    nb.v = nb.add(v, nb.mul(h2, 5.0))             # рисунок вдоль доски свой
    try:
        g = _scrap_grain(nb, lines=lines, seed=seed + 7.0)
    finally:
        nb.u, nb.v = u, v
    ksel = nb.gt(h3, 0.55)
    du = nb.mul(nb.sub(ul, nb.mad(h4, 0.5, 0.25)), 1.0 / planks)
    dv = nb.sub(nb.fract(nb.add(nb.sub(v, h4), 0.5)), 0.5)
    kd = nb.pow(nb.add(nb.pow(nb.mul(du, 1.0 / 0.016), 2.0), nb.pow(nb.mul(dv, 1.0 / 0.026), 2.0)), 0.5)
    knot = nb.mul(nb.sstep(kd, 1.0, 0.5), ksel)
    kring = nb.mul(nb.sstep(kd, 2.2, 1.0), ksel)
    bleach = nb.sstep(_gn(nb, 2.2, 2.2, detail=4.0, rough=0.55, seed=seed + 12), 0.52, 0.70)
    grime = _gn(nb, 3.5, 3.5, detail=5.0, rough=0.58, seed=seed + 13)
    grime2 = _gn(nb, 1.2, 3.0, detail=3.0, rough=0.5, seed=seed + 21)          # вытянутые вдоль доски потемнения
    st = _gn(nb, 2.6, 2.6, detail=3.0, rough=0.5, seed=seed + 14)
    stain = nb.sstep(st, 0.62, 0.68)
    stainrim = nb.mul(nb.sstep(st, 0.61, 0.63), nb.sstep(st, 0.68, 0.64))
    e = nb.absv(nb.sub(ul, 0.5))
    seamm = nb.sstep(e, 0.482, 0.496)
    bev = nb.sstep(e, 0.43, 0.482)
    sdn = _gn(nb, 10.0, 3.0, detail=3.0, rough=0.55, seed=seed + 15)
    sdirt = nb.clamp01(nb.mul(nb.sstep(e, 0.34, 0.485), nb.mad(sdn, 1.2, -0.1)))   # грязь у швов, рвано
    splash = nb.mul(nb.sstep(_gn(nb, 60.0, 60.0, detail=2.0, seed=seed + 22), 0.66, 0.70),
                    nb.sstep(_gn(nb, 2.0, 2.0, detail=2.0, seed=seed + 23), 0.50, 0.62))   # брызги грязи
    scratch = _scratches(nb, seed + 40.0, freq=20.0, width=0.014, seg=14.0, keep=0.66,
                         dirs=((1, 0), (1, 1), (1, -1), (2, 1), (2, -1)))
    fresh = nb.gt(_gn(nb, 3.0, 3.0, detail=1.0, seed=seed + 19), 0.5)
    hv = _gv(nb, 36.0, 36.0, seed=seed + 20)
    hole = nb.mul(nb.sstep(hv.outputs['Distance'], 0.14, 0.07), nb.gt(nb.sepc(hv.outputs['Color'])[0], 0.96))
    col = nb.mixc(pal['early'], pal['late'], nb.clamp01(nb.lin([(0.85, g['line']), (0.35, g['line2'])])))
    col = nb.mixc(col, pal['late'], nb.mul(g['streak'], 0.55))
    col = nb.mixc(col, pal['dirt'], nb.mul(g['band'], 0.30))
    col = nb.scalec(col, nb.mad(g['fine'], 0.20, 0.90))
    col = nb.scalec(col, nb.mad(g['fine2'], 0.12, 0.94))
    col = nb.scalec(col, nb.mad(h1, 0.26, 0.82))                                     # тон доски
    col = nb.mixc(col, pal['grey'], nb.mul(nb.gt(h3, 0.62), 0.35))                   # часть досок посерела
    col = nb.mixc(col, pal['bleach'], nb.mul(bleach, nb.mad(g['line'], -0.25, 0.55)))   # выгорело, линии остаются
    col = nb.mixc(col, pal['dirt'], nb.mul(g['line'], nb.mad(grime, 0.35, 0.05)))    # грязь в бороздках
    col = nb.mixc(col, pal['dirt'], nb.mul(g['pores'], 0.35))
    col = nb.scalec(col, nb.mad(grime, 0.40, 0.76))
    col = nb.scalec(col, nb.mad(grime2, 0.44, 0.78))
    col = nb.mixc(col, pal['dirt'], nb.clamp01(nb.lin([(0.12, stain), (0.14, stainrim)])))
    col = nb.mixc(col, pal['dirt'], nb.clamp01(nb.lin([(0.45, knot), (0.25, kring)])))
    col = nb.mixc(col, pal['dirt'], nb.mul(splash, 0.55))
    col = nb.mixc(col, pal['fresh'], nb.mul(scratch, nb.mul(fresh, 0.55)))
    col = nb.mixc(col, pal['dirt'], nb.mul(scratch, nb.mul(nb.sub(1.0, fresh), 0.40)))
    col = nb.mixc(col, pal['crack'], g['crack'])
    col = nb.mixc(col, pal['crack'], nb.mul(hole, 0.8))
    col = nb.mixc(col, pal['dirt'], nb.mul(sdirt, 0.75))
    col = nb.scalec(col, nb.sub(1.0, nb.mul(bev, 0.25)))
    col = nb.mixc(col, pal['seam'], seamm)
    height = nb.lin([(0.06, g['fine']), (0.02, g['fine2']), (0.12, g['line']), (0.04, g['line2']), (-0.22, g['pores']),
                     (-0.5, g['crack']), (0.05, knot), (-0.20, scratch), (-0.5, hole), (0.03, splash),
                     (-0.38, bev), (-0.55, seamm)], bias=0.52)
    rough = nb.clamp01(nb.lin([(0.06, g['line']), (0.05, g['fine']), (0.06, sdirt), (0.05, bleach), (0.05, g['crack']),
                               (0.04, seamm), (-0.04, stain)], bias=0.80))
    return dict(color=col, rough=rough, height=height, bump=0.010, seam=seamm)


DIRT = dict(soil=srgb(58, 49, 42), soil2=srgb(82, 74, 68), dust=srgb(118, 108, 114), damp=srgb(34, 29, 26),
            pebble=srgb(104, 100, 96), chip=srgb(140, 98, 60), chip_old=srgb(78, 56, 38), rust=srgb(100, 50, 26),
            scale=srgb(40, 36, 35), grit=srgb(150, 140, 128))


def _chips(nb, fu, fv, frac, size, seed, u=None, v=None, wobble=0.0):
    """Редкие вкрапления: ячейки Voronoi на (анизотропном) торе — при fu≠fv эллипсы вытянуты вдоль оси с меньшей
    частотой; видна доля frac ячеек, радиус size·(0.6…1.2) в единицах шума; wobble — рваный край (шум к расстоянию).
    → (маска, купол высоты, тон ячейки 0..1)."""
    vo = _gv(nb, fu, fv, seed=seed, u=u, v=v)
    rnd = nb.sepc(vo.outputs['Color'])
    d = vo.outputs['Distance']
    if wobble:
        d = nb.add(d, nb.mul(nb.sub(_gn(nb, fu * 4.0, fv * 4.0, detail=2.0, seed=seed + 0.5, u=u, v=v), 0.5), wobble))
    sel = nb.gt(rnd[0], 1.0 - frac)
    s = nb.mad(rnd[2], 0.6 * size, 0.6 * size)
    m = nb.mul(nb.sstep(d, s, nb.mul(s, 0.8)), sel)
    dome = nb.mul(nb.pow(nb.clamp01(nb.sub(1.0, nb.math('DIVIDE', d, s))), 0.5), sel)
    return m, dome, rnd[1]


def _flakes(nb, f, frac, seed):
    """Угловатые чешуйки (окалина, ржавые хлопья): часть ячеек Voronoi (координаты чуть искривлены шумом — ячейки
    неровные) целиком, отступив от рёбер и обрезав дальние углы."""
    du = nb.mul(nb.sub(_gn(nb, f * 0.5, f * 0.5, detail=2.0, seed=seed + 0.3), 0.5), 0.6 / f)
    dv = nb.mul(nb.sub(_gn(nb, f * 0.5, f * 0.5, detail=2.0, seed=seed + 0.7), 0.5), 0.6 / f)
    uu, vv = nb.add(nb.u, du), nb.add(nb.v, dv)
    vo = _gv(nb, f, f, seed=seed, u=uu, v=vv)
    ve = _gv(nb, f, f, feature='DISTANCE_TO_EDGE', seed=seed, u=uu, v=vv)
    rnd = nb.sepc(vo.outputs['Color'])
    sel = nb.gt(rnd[0], 1.0 - frac)
    m = nb.mul(nb.mul(nb.sstep(ve.outputs['Distance'], 0.03, 0.08), nb.sstep(vo.outputs['Distance'], 0.75, 0.60)), sel)
    return m, rnd[1]


def scrap_dirt_nodes(nb, seed=0.0):
    """Земля свалки под кучами и на полу: тёмная коричнево-серая смесь (крупные пятна почвы разного тона), пыльные
    лилово-серые наносы с сеткой трещинок сухой корки, тёмные влажные пятна, песчинки; вкрапления — камешки с рваным
    краем, щепки трёх ориентаций (вдоль U, вдоль V, по диагонали: тор на (u+v, u−v) тоже бесшовен), угловатые хлопья
    окалины и ржавчины. Без металличности; шероховатость 0.72 (влажное) … 0.98."""
    u, v = nb.u, nb.v
    n1 = _gn(nb, 4.0, 4.0, detail=5.0, rough=0.58, seed=seed + 1)
    n2 = _gn(nb, 12.0, 12.0, detail=3.0, rough=0.55, seed=seed + 2)
    n3 = _gn(nb, 30.0, 30.0, detail=3.0, rough=0.6, seed=seed + 15)
    lump = _gn(nb, 7.0, 7.0, detail=4.0, rough=0.6, seed=seed + 3)
    fine = _gn(nb, 200.0, 200.0, detail=2.0, rough=0.6, seed=seed + 4)
    grit = _gv(nb, 180.0, 180.0, seed=seed + 5)
    gr = nb.sepc(grit.outputs['Color'])[0]
    gritm = nb.sstep(grit.outputs['Distance'], 0.38, 0.22)
    grit_l = nb.mul(gritm, nb.gt(gr, 0.72))
    grit_d = nb.mul(gritm, nb.math('LESS_THAN', gr, 0.22))
    dust = nb.sstep(_gn(nb, 2.5, 2.5, detail=4.0, rough=0.55, seed=seed + 6), 0.52, 0.70)
    damp = nb.sstep(_gn(nb, 1.7, 1.7, detail=3.0, rough=0.5, seed=seed + 7), 0.60, 0.74)
    mc = _gv(nb, 9.0, 9.0, feature='DISTANCE_TO_EDGE', seed=seed + 8)
    mud = nb.mul(nb.sstep(mc.outputs['Distance'], 0.025, 0.0), nb.mul(dust, nb.gt(_gn(nb, 5.0, 5.0, detail=2.0, seed=seed + 9), 0.5)))
    peb, pebh, pebt = _chips(nb, 22.0, 22.0, 0.08, 0.30, seed + 10, wobble=0.18)
    chips = [_chips(nb, 60.0, 16.0, 0.12, 0.34, seed + 11, wobble=0.10),                                   # щепки вдоль V
             _chips(nb, 16.0, 60.0, 0.12, 0.34, seed + 12, wobble=0.10),                                   # вдоль U
             _chips(nb, 42.0, 11.0, 0.12, 0.34, seed + 13, u=nb.add(u, v), v=nb.sub(u, v), wobble=0.10)]   # по диагонали
    fl, flt = _flakes(nb, 46.0, 0.08, seed + 14)
    col = nb.mixc(DIRT['soil'], DIRT['soil2'], nb.sstep(n1, 0.35, 0.68))
    col = nb.scalec(col, nb.mad(n2, 0.30, 0.85))
    col = nb.scalec(col, nb.mad(n3, 0.22, 0.89))
    col = nb.scalec(col, nb.mad(fine, 0.24, 0.88))
    col = nb.mixc(col, DIRT['dust'], nb.mul(dust, 0.45))
    col = nb.mixc(col, DIRT['damp'], nb.mul(damp, 0.55))
    col = nb.mixc(col, DIRT['damp'], nb.mul(mud, 0.5))
    col = nb.mixc(col, DIRT['grit'], nb.mul(grit_l, 0.28))
    col = nb.mixc(col, srgb(22, 20, 19), nb.mul(grit_d, 0.5))
    col = nb.mixc(col, nb.scalec(DIRT['pebble'], nb.mad(pebt, 0.45, 0.75)), peb)
    chip_m = None
    chip_h = None
    for m, dome, t in chips:
        col = nb.mixc(col, nb.mixc(DIRT['chip_old'], DIRT['chip'], t), m)
        chip_m = m if chip_m is None else nb.maxv(chip_m, m)
        chip_h = dome if chip_h is None else nb.maxv(chip_h, dome)
    col = nb.mixc(col, nb.mixc(DIRT['scale'], DIRT['rust'], nb.gt(flt, 0.45)), nb.mul(fl, 0.85))
    height = nb.lin([(0.30, lump), (0.12, n2), (0.06, n3), (0.08, fine), (-0.10, damp), (-0.25, mud), (0.45, pebh),
                     (0.18, chip_m), (0.10, chip_h), (0.15, fl), (0.05, grit_l)], bias=0.15)
    rough = nb.lin([(0.04, dust), (-0.18, damp), (-0.10, peb), (-0.05, chip_m), (0.04, fine)], bias=0.93)
    rough = nb.minv(nb.maxv(rough, 0.72), 0.98)
    return dict(color=col, rough=rough, height=height, bump=0.02)


BRASS = dict(base=srgb(176, 134, 62), bright=srgb(208, 172, 98), warm=srgb(160, 104, 52), tarnish=srgb(106, 78, 40),
             patina=srgb(46, 36, 22), verdigris=srgb(84, 108, 86))


def brass_worn_nodes(nb, seed=0.0):
    """Потёртая латунь (короны на ящиках №022, накладки, уголки): тёплый жёлтый металл с медными зонами и
    полировочными штрихами вдоль U, выступы натёрты до блеска, по большим пятнам — бурая плёнка потускнения; тёмная
    патина — в низинах собственного рельефа (крупные вмятины + мелкая чеканка/раковины), редкая зелень там же; тонкие
    светлые царапины. Геометрических углублений текстура не знает. Металличность 0.95 … 0.3 (патина), 0 (зелень)."""
    hammer = _gv(nb, 18.0, 18.0, seed=seed + 1).outputs['Distance']
    ding = _gn(nb, 7.0, 7.0, detail=4.0, rough=0.55, seed=seed + 2)
    low = _gn(nb, 2.4, 2.4, detail=3.0, rough=0.5, seed=seed + 3)
    micro = _gn(nb, 28.0, 28.0, detail=3.0, rough=0.6, seed=seed + 13)
    relief = nb.lin([(1.0, ding), (0.6, low), (0.35, micro)], bias=-0.475)          # ~0.5 ± 0.12
    cav = nb.sstep(relief, 0.38, 0.30)                                               # крупные низины
    cavf = nb.mul(nb.sstep(micro, 0.37, 0.29), nb.sstep(relief, 0.60, 0.48))         # мелкие раковины
    pat = nb.clamp01(nb.maxv(cav, cavf))
    rub = nb.sstep(relief, 0.56, 0.68)                                               # выступы натёрты
    tarn = nb.mul(nb.sstep(_gn(nb, 3.0, 3.0, detail=5.0, rough=0.6, seed=seed + 4), 0.46, 0.62), nb.sub(1.0, rub))
    verd = nb.mul(nb.sstep(_gn(nb, 8.0, 8.0, detail=4.0, rough=0.6, seed=seed + 5), 0.62, 0.68), cav)
    warmz = nb.sstep(_gn(nb, 2.0, 2.0, detail=3.0, rough=0.5, seed=seed + 7), 0.45, 0.70)
    var = _gn(nb, 12.0, 12.0, detail=3.0, rough=0.5, seed=seed + 8)
    brushed = _gn(nb, 4.0, 260.0, detail=2.0, rough=0.6, seed=seed + 9)            # полировочные штрихи вдоль U
    scratch = nb.mul(_scratches(nb, seed + 30.0, freq=30.0, width=0.010, seg=8.0, keep=0.58), nb.sub(1.0, pat))
    col = nb.mixc(BRASS['base'], BRASS['warm'], nb.mul(warmz, 0.35))
    col = nb.scalec(col, nb.mad(var, 0.14, 0.93))
    col = nb.scalec(col, nb.mad(brushed, 0.22, 0.89))
    col = nb.mixc(col, BRASS['bright'], nb.mul(rub, 0.30))
    col = nb.mixc(col, BRASS['tarnish'], nb.mul(tarn, 0.40))
    col = nb.mixc(col, BRASS['patina'], nb.mul(pat, 0.88))
    col = nb.mixc(col, BRASS['verdigris'], nb.mul(verd, 0.7))
    col = nb.mixc(col, BRASS['bright'], nb.mul(scratch, 0.55))
    height = nb.lin([(0.60, relief), (0.10, nb.mul(hammer, hammer)), (-0.15, cavf), (0.03, brushed), (-0.20, scratch),
                     (0.05, verd)], bias=0.1)
    rough = nb.lerp(nb.lin([(0.10, var), (0.08, brushed)], bias=0.24), 0.55, tarn)
    rough = nb.lerp(rough, 0.24, nb.mul(rub, 0.8))
    rough = nb.lerp(rough, 0.85, nb.mul(pat, 0.9))
    rough = nb.lerp(rough, 0.92, verd)
    rough = nb.lerp(rough, 0.26, scratch)
    metal = nb.lerp(0.95, 0.85, tarn)
    metal = nb.lerp(metal, 0.3, nb.mul(pat, 0.9))
    metal = nb.lerp(metal, 0.0, verd)
    return dict(color=col, rough=rough, height=height, bump=0.015, metal=metal)


MATERIALS.update({
    'rust_metal': (lambda nb: rust_metal_nodes(nb, seed=50.0), 2048),
    'rust_painted_red': (lambda nb: rust_painted_nodes(nb, PAINT_SCRAP_RED, seed=60.0), 1024),
    'scrap_wood': (lambda nb: scrap_wood_nodes(nb, planks=4, seed=31.0), 2048),
    'scrap_dirt': (lambda nb: scrap_dirt_nodes(nb, seed=70.0), 2048),
    'brass_worn': (lambda nb: brass_worn_nodes(nb, seed=80.0), 1024),
})
SCRAP_SETS = ['rust_metal', 'rust_painted_red', 'scrap_wood', 'scrap_dirt', 'brass_worn']

_bake_material_v3 = bake_material


def _height_to_normal(h, dist, base=None, gain=1.4):
    """Карта высот (строки снизу вверх, как в Blender) → нормаль в касательном пространстве (OpenGL, +Y = +V).
    Градиент — центральные разности через np.roll: тайл периодичен, значит и нормаль на стыке бесшовна.
    Наклон как у ноды Bump на плоскости запекания 2×2 м (1 тайл = 2 м): n ∝ (−d·∂h/∂u / 2, −d·∂h/∂v / 2, 1).
    base — RGB 0..1 нормали слоя-основы: смешивание whiteout (xy складываются, z перемножаются).
    gain 1.4 — сверка с Bump (filter width 0.1 px): на одном графе scrap_dirt Bump давал std нормали ≈1.45× больше
    разности через 2 px, так что сила новых наборов сопоставима со старыми."""
    size = h.shape[0]
    dhdu = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * size
    dhdv = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * size
    k = -dist * gain * 0.5
    n = np.stack([k * dhdu, k * dhdv, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    if base is not None:
        b = base * 2.0 - 1.0
        n = np.stack([b[..., 0] + n[..., 0], b[..., 1] + n[..., 1], b[..., 2] * n[..., 2]], axis=-1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def _bake_scrap(name, build, size, samples=4):
    """Как bake_material v2 (плоскость 2×2 м, UV 0..1, EMIT для albedo/roughness), но: высота печётся EMIT-ом во
    float и нормаль считается в numpy (_height_to_normal) — без ноды Bump, которая трижды вычисляет граф высоты и
    на больших графах упирается в стек SVM Cycles (плоская нормаль); metal-сокет → metallic.png EMIT-ом (карта, а не
    константа); ch['normal_rgb'] (слой-основа из _pbr_layer) смешивается с рельефом."""
    t0 = time.time()
    out_dir = os.path.join(PBR, name)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = _setup_cycles(samples)
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    plane.name = 'Bake_' + name
    mat = bpy.data.materials.new('Bake_' + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    plane.data.materials.append(mat)
    nb = NB(nt)
    ch = build(nb)
    tb = time.time() - t0
    out = nb.new('ShaderNodeOutputMaterial')
    emit = nb.new('ShaderNodeEmission')
    emit.inputs['Strength'].default_value = 1.0
    nt.links.new(emit.outputs['Emission'], out.inputs['Surface'])
    tex = nb.new('ShaderNodeTexImage')
    nt.nodes.active = tex
    bpy.ops.object.select_all(action='DESELECT')
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    scn.cycles.samples = samples

    def bake(source):
        img = bpy.data.images.new('__bake', size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = 'Non-Color'
        tex.image = img
        nt.nodes.active = tex
        for l in list(emit.inputs['Color'].links):
            nt.links.remove(l)
        nb.plug(emit.inputs['Color'], source)
        bpy.ops.object.bake(type='EMIT')
        arr = _read_float(img)
        bpy.data.images.remove(img)
        return arr

    def gray8(arr):
        g8 = np.clip(np.rint(np.clip(arr, 0, 1) * 255.0), 0, 255).astype(np.uint8)
        g8[..., 1] = g8[..., 0]
        g8[..., 2] = g8[..., 0]
        g8[..., 3] = 255
        return g8

    a8 = _linear_to_srgb8(bake(ch['color']))
    a8[..., 3] = 255
    if a8[..., :3].max() == 0:
        raise RuntimeError(name + ': чёрное albedo — вероятно, «out of SVM stack space» (граф слишком большой)')
    save_rgba8(os.path.join(out_dir, 'albedo.png'), a8)
    r8 = gray8(bake(ch['rough']))
    save_rgba8(os.path.join(out_dir, 'roughness.png'), r8)
    hgt = bake(ch['height'])[..., 0].astype(np.float64)
    base = bake(ch['normal_rgb'])[..., :3].astype(np.float64) if ch.get('normal_rgb') is not None else None
    if float(hgt.std()) == 0.0:
        raise RuntimeError(name + ': плоская высота — вероятно, «out of SVM stack space»')
    n = _height_to_normal(hgt, ch['bump'], base)
    n8 = np.zeros((size, size, 4), dtype=np.uint8)
    n8[..., :3] = np.clip(np.rint((n * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)
    n8[..., 3] = 255
    save_rgba8(os.path.join(out_dir, 'normal.png'), n8)
    info = ''
    m = ch.get('metal')
    if isinstance(m, bpy.types.NodeSocket):
        m8 = gray8(bake(m))
        save_rgba8(os.path.join(out_dir, 'metallic.png'), m8)
        info = '  metallic map mean %.2f (>0.5: %.0f%%)' % (m8[..., 0].mean() / 255.0, 100.0 * (m8[..., 0] > 127).mean())
    elif m is not None:
        m8 = np.full((size, size, 4), int(round(m * 255)), dtype=np.uint8)
        m8[..., 3] = 255
        save_rgba8(os.path.join(out_dir, 'metallic.png'), m8)
    print('baked %-16s %4d² in %5.1fs (граф %d нод, сборка %.1fs)  albedo mean sRGB %s  rough %.2f–%.2f  normal std %s%s' % (
        name, size, time.time() - t0, len(nt.nodes), tb, a8[..., :3].reshape(-1, 3).mean(0).round(1),
        np.percentile(r8[..., 0], 1) / 255.0, np.percentile(r8[..., 0], 99) / 255.0,
        n8[..., :3].reshape(-1, 3).std(0).round(1), info))


def bake_material(name, build, size, samples=4):
    """v4 (THE SCRAP): наборы SCRAP_SETS печёт _bake_scrap (карта металличности, нормаль слоя-основы); остальные —
    прежним путём (v3 → v2) без изменений."""
    if bpy is None:
        raise RuntimeError('нужен Blender')
    if name in SCRAP_SETS:
        return _bake_scrap(name, build, size, samples)
    return _bake_material_v3(name, build, size, samples)


# ----------------------------------------------------------------------------------------------------------------------
# Превью THE SCRAP: рендер плашек/шаров в Blender (textured_material из common.py — тот же путь, что у пропсов) при
# нейтральном и закатном свете + лист на Pillow: 2×2 тайла, стык тайлов 1:1, каналы, кропы листов-референсов.
# ----------------------------------------------------------------------------------------------------------------------
SCRAP_PREVIEW = os.path.abspath(os.path.join(GODOT, '..', 'docs', 'plan-demo', 'img', 'scrap-materials-v1.png'))
SCRAP_REFS = os.path.abspath(os.path.join(GODOT, '..', 'docs', 'refs', 'biomes', '01-scrap'))
SCRAP_REF_CROPS = {   # материал → (лист, кроп x0, y0, x1, y1, подпись)
    'rust_metal': ('sheet-02.png', (262, 640, 510, 800), '034 Metal Plate'),
    'rust_painted_red': ('sheet-02.png', (1290, 160, 1530, 310), '026 Metal Barrel'),
    'scrap_wood': ('sheet-02.png', (10, 170, 258, 310), '021 Wooden Crate'),
    'scrap_dirt': ('scenes.png', (300, 790, 600, 880), '05 Crusher Area: земля'),
    'brass_worn': ('sheet-02.png', (262, 170, 510, 310), '022 Reinforced Crate'),
}


def scrap_preview_render(tmp_dir, names=None):
    """Blender: на материал — плашка 0.8×0.8 м (uv_box, V вверх) и шар диаметром 0.72 м (uv_cylinder_along, 1 тайл = 1 м);
    ортокамера спереди; два света: нейтральный (белое солнце + серое небо) и закатный, как на листах
    (оранжевое низкое солнце + лиловое небо). → tmp_dir/scrap_neutral.png, scrap_sunset.png (RGBA, фон прозрачный)."""
    names = names or SCRAP_SETS
    sys.path.insert(0, HERE)
    import common as C
    C.reset_scene()
    scn = _setup_cycles(48)
    scn.cycles.samples = 48
    scn.cycles.use_denoising = True
    scn.render.film_transparent = True
    scn.render.resolution_x = 1600
    scn.render.resolution_y = 600
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    for i, n in enumerate(names):
        x = i * 1.1
        mat = C.textured_material('Scrap_' + n, n)
        slab = C.add_cube('Slab_' + n, (0.8, 0.06, 0.8), (x, 0.0, 1.46))
        C.uv_box(slab, 1.0)
        C.bevel(slab, 0.012, 2)
        C.smooth(slab)
        C.assign(slab, mat)
        ball = C.add_sphere('Ball_' + n, 0.36, (x, 0.0, 0.42), segments=96, rings=48)
        C.uv_cylinder_along(ball, 'Z', 1.0)
        C.smooth(ball)
        C.assign(ball, mat)
    cam_data = bpy.data.cameras.new('Cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 5.7
    cam = bpy.data.objects.new('Cam', cam_data)
    scn.collection.objects.link(cam)
    tilt = math.radians(8.0)
    cam.location = (2.2, -10.0, 0.98 + 10.0 * math.tan(tilt))
    cam.rotation_euler = (math.pi / 2 - tilt, 0.0, 0.0)
    scn.camera = cam
    sun_data = bpy.data.lights.new('Sun', 'SUN')
    sun_data.angle = math.radians(4.0)
    sun = bpy.data.objects.new('Sun', sun_data)
    scn.collection.objects.link(sun)
    world = bpy.data.worlds.new('World')
    scn.world = world
    world.use_nodes = True
    wn = world.node_tree
    bg = wn.nodes['Background']
    tc = wn.nodes.new('ShaderNodeTexCoord')
    sep = wn.nodes.new('ShaderNodeSeparateXYZ')
    mix = wn.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    wn.links.new(tc.outputs['Generated'], sep.inputs[0])
    mr = wn.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = -0.3
    mr.inputs['From Max'].default_value = 0.8
    wn.links.new(sep.outputs['Z'], mr.inputs['Value'])
    wn.links.new(mr.outputs['Result'], mix.inputs[0])
    wn.links.new(mix.outputs[2], bg.inputs['Color'])
    setups = {
        'neutral': dict(col=(1.0, 1.0, 1.0), e=3.2, rot=(math.radians(50), 0.0, math.radians(-35)), ground=(0.10, 0.10, 0.10), sky=(0.36, 0.36, 0.36)),
        'sunset': dict(col=(1.0, 0.56, 0.30), e=4.0, rot=(math.radians(72), 0.0, math.radians(-68)), ground=(0.05, 0.04, 0.05), sky=(0.16, 0.13, 0.26)),
    }
    for key, s in setups.items():
        sun_data.color = s['col']
        sun_data.energy = s['e']
        sun.rotation_euler = s['rot']
        mix.inputs[6].default_value = s['ground'] + (1.0,)
        mix.inputs[7].default_value = s['sky'] + (1.0,)
        scn.render.filepath = os.path.join(tmp_dir, 'scrap_%s.png' % key)
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        print('render', key, '%.1fs' % (time.time() - t0), scn.render.filepath)


def _seam_ratio(a):
    """Отношение средней разницы через стык тайла (последний ↔ первый столбец/строка) к средней разнице соседних
    столбцов/строк внутри: ≈1 — шва нет, заметно >1.5 — шов."""
    a = a.astype(np.float64)
    inner_u = np.abs(np.diff(a, axis=1)).mean()
    inner_v = np.abs(np.diff(a, axis=0)).mean()
    wrap_u = np.abs(a[:, 0] - a[:, -1]).mean()
    wrap_v = np.abs(a[0, :] - a[-1, :]).mean()
    return wrap_u / max(inner_u, 1e-6), wrap_v / max(inner_v, 1e-6)


def scrap_sheet(tmp_dir=None, names=None):
    """Pillow (системный python3): превью-лист THE SCRAP → docs/plan-demo/img/scrap-materials-v1.png.
    Ряды: рендер (нейтральный свет), рендер (закат, как на листах), albedo 2×2 тайла (1 тайл = 1 м), стык четырёх
    тайлов 1:1 (центр кропа — угол тайла), roughness / metallic / normal, кроп листа-референса. Печатает seam-ratio."""
    from PIL import Image, ImageDraw, ImageFont
    names = names or SCRAP_SETS
    tmp_dir = tmp_dir or os.environ.get('SCRAP_PREVIEW_TMP') or os.path.join(__import__('tempfile').gettempdir(), 'scrap_preview')
    font = None
    for fp in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf'):
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 15)
            small = ImageFont.truetype(fp, 12)
            big = ImageFont.truetype(fp, 22)
            break
    if font is None:
        font = small = big = ImageFont.load_default()
    col_w, pad, lab = 320, 10, 20
    W = pad + len(names) * col_w + pad
    bgc = (22, 21, 24)
    blocks = []

    def label(draw, xy, text, f=None, fill=(226, 222, 214)):
        draw.text(xy, text, fill=fill, font=f or font)

    # рендеры
    for key, title in (('neutral', 'нейтральный свет'), ('sunset', 'закатный свет (как на листах)')):
        p = os.path.join(tmp_dir, 'scrap_%s.png' % key)
        if not os.path.exists(p):
            print('нет рендера', p, '— сначала Blender … -- --scrap-preview')
            continue
        im = Image.open(p).convert('RGBA')
        im = im.resize((len(names) * col_w, int(im.height * len(names) * col_w / im.width)), Image.LANCZOS)
        blk = Image.new('RGB', (W, im.height + lab + pad), bgc)
        blk.paste(im, (pad, lab), im)
        d = ImageDraw.Draw(blk)
        label(d, (pad, 2), 'Рендер, ' + title + ': плашка 0.8 × 0.8 м и шар диаметром 0.72 м, 1 тайл = 1 м', small, (170, 166, 160))
        blocks.append(blk)
    # albedo 2×2, стык 1:1, каналы, референс
    tile = 150
    ch_h = 100
    rows_h = lab + 2 * tile + pad + lab + 2 * tile + pad + lab + ch_h + pad + lab + 200 + pad
    blk = Image.new('RGB', (W, rows_h), bgc)
    d = ImageDraw.Draw(blk)
    for ci, n in enumerate(names):
        x0 = pad + ci * col_w
        y = 0
        ap = os.path.join(PBR, n, 'albedo.png')
        if not os.path.exists(ap):
            label(d, (x0, y + 2), n + ': нет albedo.png')
            continue
        alb = Image.open(ap).convert('RGB')
        S = alb.width
        label(d, (x0, y + 2), '%s  %d²  albedo 2×2' % (n, S))
        small_t = alb.resize((tile, tile), Image.LANCZOS)
        for dx in (0, 1):
            for dy in (0, 1):
                blk.paste(small_t, (x0 + dx * tile, y + lab + dy * tile))
        y += lab + 2 * tile + pad
        big2 = Image.new('RGB', (2 * S, 2 * S))
        for dx in (0, 1):
            for dy in (0, 1):
                big2.paste(alb, (dx * S, dy * S))
        crop = big2.crop((S - tile, S - tile, S + tile, S + tile))
        blk.paste(crop, (x0, y + lab))
        su, sv = _seam_ratio(np.asarray(alb).mean(axis=2))
        label(d, (x0, y + 2), 'стык 4 тайлов 1:1 (центр), seam u %.2f v %.2f' % (su, sv), small)
        y += lab + 2 * tile + pad
        label(d, (x0, y + 2), 'roughness · metallic · normal', small)
        for k, chn in enumerate(('roughness', 'metallic', 'normal')):
            cp = os.path.join(PBR, n, chn + '.png')
            if os.path.exists(cp):
                c = Image.open(cp).convert('RGB').resize((ch_h, ch_h), Image.LANCZOS)
                blk.paste(c, (x0 + k * (ch_h + 3), y + lab))
                a = np.asarray(Image.open(cp).convert('L')).astype(np.float32) / 255.0
                label(d, (x0 + k * (ch_h + 3) + 2, y + lab + ch_h - 16), '%.2f–%.2f' % (np.percentile(a, 1), np.percentile(a, 99)), small, (255, 255, 120))
            else:
                label(d, (x0 + k * (ch_h + 3) + 4, y + lab + ch_h // 2), '—', font)
        y += lab + ch_h + pad
        ref = SCRAP_REF_CROPS.get(n)
        if ref and os.path.exists(os.path.join(SCRAP_REFS, ref[0])):
            r = Image.open(os.path.join(SCRAP_REFS, ref[0])).convert('RGB').crop(ref[1])
            r.thumbnail((col_w - 10, 200), Image.LANCZOS)
            blk.paste(r, (x0, y + lab))
            label(d, (x0, y + 2), 'референс: ' + ref[2] + ' (' + ref[0] + ')', small, (170, 166, 160))
    blocks.append(blk)
    head = Image.new('RGB', (W, 40), bgc)
    label(ImageDraw.Draw(head), (pad, 8), 'THE SCRAP — PBR v1: ' + ' · '.join(names), big)
    blocks.insert(0, head)
    H = sum(b.height for b in blocks)
    sheet = Image.new('RGB', (W, H), bgc)
    y = 0
    for b in blocks:
        sheet.paste(b, (0, y))
        y += b.height
    os.makedirs(os.path.dirname(SCRAP_PREVIEW), exist_ok=True)
    sheet.save(SCRAP_PREVIEW)
    print('scrap preview', SCRAP_PREVIEW, sheet.size)
    for n in names:
        for chn in ('albedo', 'roughness', 'normal', 'metallic'):
            cp = os.path.join(PBR, n, chn + '.png')
            if os.path.exists(cp):
                a = np.asarray(Image.open(cp).convert('RGB')).astype(np.float64)
                su, sv = _seam_ratio(a.mean(axis=2))
                print('  %-17s %-9s mean %s  seam u %.2f v %.2f' % (n, chn, a.reshape(-1, 3).mean(0).round(1), su, sv))


_main_v3 = main


def main():
    """v4: + --scrap-preview (Blender: рендер плашек/шаров THE SCRAP, затем лист через системный python3)
    и --scrap-sheet [tmp] (системный python3 + Pillow: только сборка листа). Остальное — прежний main."""
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if '--scrap-sheet' in argv:
        i = argv.index('--scrap-sheet')
        scrap_sheet(argv[i + 1] if i + 1 < len(argv) else None)
        return
    if '--scrap-preview' in argv:
        if bpy is None:
            print('нужен Blender (или --scrap-sheet для системного python)')
            sys.exit(2)
        import shutil
        import subprocess
        import tempfile
        tmp = os.environ.get('SCRAP_PREVIEW_TMP') or os.path.join(tempfile.gettempdir(), 'scrap_preview')
        os.makedirs(tmp, exist_ok=True)
        scrap_preview_render(tmp)
        py = shutil.which('python3') or '/usr/bin/python3'
        cmd = [py, os.path.abspath(__file__), '--scrap-sheet', tmp]
        # Blender под Rosetta (x86_64): дочерний python3 унаследует архитектуру, а numpy/Pillow системы — arm64
        try:
            rosetta = subprocess.run(['sysctl', '-n', 'sysctl.proc_translated'], capture_output=True, text=True).stdout.strip() == '1'
        except OSError:
            rosetta = False
        if rosetta and os.path.exists('/usr/bin/arch'):
            cmd = ['/usr/bin/arch', '-arm64'] + cmd
        env = {k: v for k, v in os.environ.items() if not k.startswith('PYTHON')}
        subprocess.run(cmd, check=True, env=env)
        return
    _main_v3()


if __name__ == '__main__':
    main()
