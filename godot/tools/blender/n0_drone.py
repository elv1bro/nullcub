"""N0 — дрон-ведущий NULL Arena (лист автора «N0 · NULL ARENA HOST», 30.09.2026; описание — docs/plan-demo/ART_NULL.md).

Запуск (Blender 4.5 LTS):
  blender -b --python n0_drone.py -- --export               → assets/models/n0/n0.glb + n0_face_atlas.png
  blender -b --python n0_drone.py -- --preview out.png      → разворот front / 3/4 / side / back (Cycles)
  blender -b --python n0_drone.py -- --preview out.png --livery event --face 1

Геометрия в координатах Godot (craft_parts.G2B): Y вверх, лицо-экран смотрит в +Z (к камере), центр шара корпуса в нуле.
Высота ~1.2 м: шар R = 0.33, уши до +0.78, пластины-ножки до −0.47.

Узлы glb (origin каждого — его шарнир, чтобы Godot анимировал поворотом):
  N0_Body     корпус: панели ливреи, тёмное ядро, обойма экрана, боковые объективы, антенны, двигатель, герб на спине
  N0_Screen   экран-лицо (UV [0..1] на ячейку атласа выражений; Godot выбирает выражение uv1_offset)
  N0_Ear_L/R  уши-плавники (шарнир у основания, ось X)
  N0_Legs_L/R пластины-ножки (шарнир у корпуса)
  N0_Arm_R    рука с микрофоном (плечо), N0_Arm_L — сложенная рука-инструмент
  N0_Mic      микрофон с кубиком «N0» (origin — хват)

Материалы по ролям (в glb плоские, настоящие ставит Godot; в превью — PBR paint_marks / iron):
  N0_Livery (кремовая ливрея), N0_Accent (жёлтые края и спина), N0_Mech (тёмный металл), N0_Joint (шарниры),
  N0_Screen (чёрное стекло + эмиссия атласа), N0_Lens (голубое стекло объективов), N0_Glow (свечение двигателя),
  N0_Rubber (поролон микрофона), N0_Print (чёрная печать: «N0», корона), N0_Flag (белый кубик микрофона).
Ливреи с листа: default (кремовая + жёлтый), event (красная), support (синяя) — LIVERIES ниже, те же числа в Godot.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402
import craft_parts as K  # noqa: E402
from craft_parts import G2B, T, Rz, Rx, S, align_y, revolve, sphere, sweep, extrude2d, torus, box, fin  # noqa: E402,F401

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(GODOT, "assets", "models", "n0")
ATLAS_PNG = os.path.join(OUT_DIR, "n0_face_atlas.png")
TRI_BUDGET = 40000

R = 0.33                 # радиус шара корпуса
SCREEN_TH = 40.0         # угол раскрытия экрана от оси +Z, градусы
GAP = 1.3                # зазор между панелями ливреи, градусы (в щели видно тёмное ядро)
SHELL_T = 0.014          # толщина панели

# ливреи: (основной, акцент) — sRGB 0..255; в превью tint paint_marks = линейный цвет / 0.82 (среднее albedo набора)
LIVERIES = {
    "default": ((226, 214, 190), (236, 168, 34)),
    "event": ((196, 38, 34), (236, 214, 190)),
    "support": ((38, 104, 178), (226, 214, 190)),
}
GLOW = (0.25, 0.7, 1.0)   # голубое свечение экрана, объективов, двигателя (линейный)

# атлас выражений: 5 × 2 ячеек, порядок как на листе
EXPRESSIONS = ["default", "happy", "excited", "shocked", "curious", "worried", "confused", "angry", "sad", "glitch"]
ATLAS_COLS, ATLAS_ROWS, CELL = 5, 2, 256


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(rgb):
    return tuple(srgb_to_lin(v) for v in rgb) + (1.0,)


def setup_materials(livery="default", export=False, face=0):
    main, acc = LIVERIES[livery]
    ml, al = lin(main), lin(acc)
    tint = lambda c: (c[0] / 0.82, c[1] / 0.82, c[2] / 0.82, 1.0)  # noqa: E731
    K.MAT_DEFS.update({
        "N0_Livery": ("paint_marks", {"tint": tint(ml), "roughness_scale": 0.7}, (ml, 0.45), 2.5),
        "N0_Accent": ("paint_marks", {"tint": tint(al), "roughness_scale": 0.7}, (al, 0.45), 2.5),
    })
    K.FLAT.update({
        "N0_Mech": ((0.075, 0.078, 0.088, 1.0), 0.42, 0.75),
        "N0_Joint": ((0.04, 0.04, 0.045, 1.0), 0.32, 0.9),
        "N0_Rubber": ((0.035, 0.034, 0.034, 1.0), 0.95, 0.0),
        "N0_Print": ((0.025, 0.022, 0.02, 1.0), 0.6, 0.0),
        "N0_Flag": ((0.80, 0.78, 0.74, 1.0), 0.5, 0.0),
    })
    K.FORCE_FLAT = export
    K._MATS["N0_Lens"] = C.material("N0_Lens", (0.01, 0.03, 0.06, 1.0), 0.05, 0.0, emission=GLOW + (1.0,),
                                    emission_strength=0.0 if export else 0.6)
    K._MATS["N0_Glow"] = C.material("N0_Glow", (0.1, 0.3, 0.5, 1.0), 0.3, 0.0, emission=GLOW + (1.0,),
                                    emission_strength=1.0 if export else 6.0)
    K._MATS["N0_Screen"] = screen_material(export, face)


def screen_material(export, face):
    """Чёрное глянцевое стекло; в превью — эмиссия из атласа, ячейка face (UV экрана [0..1] → ячейка через Mapping)."""
    mat = C.material("N0_Screen", (0.006, 0.008, 0.012, 1.0), 0.08, 0.0)
    if export or not os.path.exists(ATLAS_PNG):
        return mat
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    uv = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    col, row = face % ATLAS_COLS, face // ATLAS_COLS
    mp.inputs['Scale'].default_value = (1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS, 1.0)
    # Blender: v снизу вверх; строка 0 атласа — верхняя половина картинки
    mp.inputs['Location'].default_value = (col / ATLAS_COLS, 1.0 - (row + 1) / ATLAS_ROWS, 0.0)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(ATLAS_PNG, check_existing=True)
    tex.extension = 'EXTEND'
    nt.links.new(uv.outputs['UV'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = 3.0
    return mat


# ----------------------------------------------------------------------------------------------------------------------
# атлас выражений экрана (numpy): голубые LED-фигуры с ореолом на чёрном, 5 × 2 ячеек по 256 px
# ----------------------------------------------------------------------------------------------------------------------
def make_face_atlas(path):
    import numpy as np
    n = CELL
    ys, xs = np.mgrid[0:n, 0:n]
    u = (xs + 0.5) / n                 # 0..1 слева направо
    v = 1.0 - (ys + 0.5) / n           # 0..1 снизу вверх

    def seg(ax, ay, bx, by, w):
        pax, pay = u - ax, v - ay
        bax, bay = bx - ax, by - ay
        h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay + 1e-9), 0.0, 1.0)
        return np.hypot(pax - bax * h, pay - bay * h) - w

    def pill(cx, cy, hw, hh):          # вертикальная таблетка
        r = hw
        return seg(cx, cy - hh + r, cx, cy + hh - r, r)

    def ring(cx, cy, r, w):
        return np.abs(np.hypot(u - cx, v - cy) - r) - w

    def disc(cx, cy, r):
        return np.hypot(u - cx, v - cy) - r

    def arc(cx, cy, r, a0, a1, w, steps=24):
        d = np.full(u.shape, 9.0)
        pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
                cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            d = np.minimum(d, seg(x0, y0, x1, y1, w))
        return d

    def star(cx, cy, r, w):
        d = seg(cx - r, cy, cx + r, cy, w)
        d = np.minimum(d, seg(cx, cy - r, cx, cy + r, w))
        d = np.minimum(d, seg(cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5, w * 0.7))
        return np.minimum(d, seg(cx - r * 0.5, cy + r * 0.5, cx + r * 0.5, cy - r * 0.5, w * 0.7))

    def cross(cx, cy, r, w):
        return np.minimum(seg(cx - r, cy - r, cx + r, cy + r, w), seg(cx - r, cy + r, cx + r, cy - r, w))

    L, Rr = 0.35, 0.65                 # центры глаз
    W = 0.018                          # толщина линий
    faces = {
        "default": lambda: np.minimum(pill(L, 0.54, 0.045, 0.15), pill(Rr, 0.54, 0.045, 0.15)),
        "happy": lambda: np.minimum.reduce([arc(L, 0.50, 0.075, 20, 160, W * 1.4), arc(Rr, 0.50, 0.075, 20, 160, W * 1.4),
                                            arc(0.5, 0.40, 0.12, 200, 340, W)]),
        "excited": lambda: np.minimum.reduce([star(L, 0.56, 0.09, W), star(Rr, 0.56, 0.09, W),
                                              arc(0.5, 0.38, 0.10, 190, 350, W * 1.3)]),
        "shocked": lambda: np.minimum.reduce([ring(L, 0.57, 0.075, W), ring(Rr, 0.57, 0.075, W), ring(0.5, 0.32, 0.045, W)]),
        "curious": lambda: np.minimum.reduce([pill(L, 0.52, 0.045, 0.10), pill(Rr, 0.58, 0.05, 0.16),
                                              seg(Rr - 0.07, 0.80, Rr + 0.06, 0.84, W * 0.8)]),
        "worried": lambda: np.minimum.reduce([pill(L, 0.50, 0.04, 0.10), pill(Rr, 0.50, 0.04, 0.10),
                                              seg(L - 0.07, 0.66, L + 0.07, 0.72, W * 0.8), seg(Rr - 0.07, 0.72, Rr + 0.07, 0.66, W * 0.8),
                                              arc(0.5, 0.22, 0.10, 55, 125, W)]),
        "confused": lambda: np.minimum.reduce([cross(L, 0.56, 0.06, W), ring(Rr, 0.56, 0.06, W),
                                               seg(0.40, 0.32, 0.47, 0.36, W), seg(0.47, 0.36, 0.53, 0.30, W), seg(0.53, 0.30, 0.60, 0.34, W)]),
        "angry": lambda: np.minimum.reduce([pill(L, 0.50, 0.045, 0.10), pill(Rr, 0.50, 0.045, 0.10),
                                            seg(L - 0.08, 0.72, L + 0.07, 0.64, W), seg(Rr - 0.07, 0.64, Rr + 0.08, 0.72, W),
                                            seg(0.42, 0.30, 0.58, 0.30, W)]),
        "sad": lambda: np.minimum.reduce([pill(L, 0.48, 0.04, 0.09), pill(Rr, 0.48, 0.04, 0.09),
                                          seg(L - 0.07, 0.62, L + 0.06, 0.66, W * 0.8), seg(Rr - 0.06, 0.66, Rr + 0.07, 0.62, W * 0.8),
                                          arc(0.5, 0.20, 0.11, 60, 120, W)]),
        "glitch": lambda: np.minimum(pill(L, 0.54, 0.045, 0.15), pill(Rr, 0.54, 0.045, 0.15)),
    }
    atlas = np.zeros((ATLAS_ROWS * n, ATLAS_COLS * n, 3), np.float32)
    blue = np.array(GLOW, np.float32)
    purple = np.array((0.55, 0.2, 1.0), np.float32)
    rng = np.random.default_rng(7)
    scan = 0.78 + 0.22 * np.cos((ys % 6) / 6.0 * 2 * math.pi)       # LED-строки, как на листе
    for i, name in enumerate(EXPRESSIONS):
        d = faces[name]()
        core = np.clip(0.5 - d * n / 1.5, 0.0, 1.0)                  # сглаженный край в полтора пикселя
        glow = np.exp(-np.maximum(d, 0.0) / 0.035) * 0.28
        val = np.clip(core * scan + glow, 0.0, 1.2)
        col = blue
        if name == "glitch":
            col = purple
            shift = np.zeros(n, np.int64)
            for band in range(6):                                    # полосы со сдвигом по горизонтали
                y0 = rng.integers(40, n - 40)
                shift[y0:y0 + rng.integers(4, 16)] = rng.integers(-24, 24)
            val = np.stack([np.roll(val[y], shift[y]) for y in range(n)])
            val += (rng.random((n, n)) < 0.012) * 0.8                # «битые пиксели»
        img = val[..., None] * col[None, None, :]
        r0, c0 = (i // ATLAS_COLS) * n, (i % ATLAS_COLS) * n
        atlas[r0:r0 + n, c0:c0 + n] = img
    atlas = np.clip(atlas, 0.0, 1.0)
    h, w = atlas.shape[:2]
    im = bpy.data.images.new("n0_face_atlas", w, h, alpha=False)
    rgba = np.concatenate([atlas, np.ones((h, w, 1), np.float32)], axis=2)
    im.pixels.foreach_set(np.flipud(rgba).ravel())                  # Blender хранит строки снизу вверх
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.filepath_raw = path
    im.file_format = 'PNG'
    im.save()
    bpy.data.images.remove(im)
    print("face atlas →", path, (w, h))


# ----------------------------------------------------------------------------------------------------------------------
# геометрия
# ----------------------------------------------------------------------------------------------------------------------
def sdir(th, ph):
    """Направление по углам: th — от оси +Z (лицо), ph — вокруг +Z от +X к +Y (0 справа, 90 вверх, 180 слева, 270 вниз)."""
    t, p = math.radians(th), math.radians(ph)
    return Vector((math.sin(t) * math.cos(p), math.sin(t) * math.sin(p), math.cos(t)))


def patch(name, mat, th0, th1, ph0, ph1, r_in=R - SHELL_T * 0.5, r_out=R + SHELL_T * 0.5, closed=False, nth=None, nph=None):
    """Панель-кусок сферической оболочки между углами (с толщиной); closed — полное кольцо по ph (без боковых стенок).
    th1 = 180 — полюс сзади закрывается в точку."""
    nth = nth or max(2, int(abs(th1 - th0) / 5.0))
    span = 360.0 if closed else (ph1 - ph0)
    nph = nph or max(2, int(abs(span) / 5.0))
    bm = bmesh.new()
    pole = th1 >= 179.999
    rows_o, rows_i = [], []
    cols = nph if closed else nph + 1
    for a in range(nth + 1):
        th = th0 + (th1 - th0) * a / nth
        if pole and a == nth:
            rows_o.append([bm.verts.new(Vector((0, 0, -r_out)))] * cols)
            rows_i.append([bm.verts.new(Vector((0, 0, -r_in)))] * cols)
            continue
        ro, ri = [], []
        for b in range(cols):
            ph = ph0 + span * b / nph
            d = sdir(th, ph)
            ro.append(bm.verts.new(d * r_out))
            ri.append(bm.verts.new(d * r_in))
        rows_o.append(ro)
        rows_i.append(ri)

    def quad(a, b, c, d):
        vs = [a, b, c, d]
        uniq = []
        for x in vs:
            if x not in uniq:
                uniq.append(x)
        if len(uniq) >= 3:
            try:
                bm.faces.new(uniq)
            except ValueError:
                pass

    ncol = cols if closed else cols - 1
    for a in range(nth):
        for b in range(ncol):
            b1 = (b + 1) % cols
            quad(rows_o[a][b], rows_o[a + 1][b], rows_o[a + 1][b1], rows_o[a][b1])
            quad(rows_i[a][b1], rows_i[a + 1][b1], rows_i[a + 1][b], rows_i[a][b])
    # стенки: верхний и нижний край по th
    for b in range(ncol):
        b1 = (b + 1) % cols
        quad(rows_o[0][b1], rows_i[0][b1], rows_i[0][b], rows_o[0][b])
        if not pole:
            quad(rows_o[nth][b], rows_i[nth][b], rows_i[nth][b1], rows_o[nth][b1])
    if not closed:
        for a in range(nth):
            quad(rows_o[a][0], rows_i[a][0], rows_i[a + 1][0], rows_o[a + 1][0])
            quad(rows_o[a + 1][-1], rows_i[a + 1][-1], rows_i[a][-1], rows_o[a][-1])
    o = K._obj(name, bm, mat)
    return fin(o, bevel=0.0035, segs=1, angle=50.0)


def leaf(n_side, length, w_base, w_max, w_tip, at=0.38, tip_round=0.35):
    """Контур листа-плавника в плоскости XY: основание в нуле, вершина на +Y, ширина по X (асимметрии нет)."""
    right, left = [], []
    for k in range(n_side + 1):
        t = k / n_side
        y = length * t
        if t < at:
            w = w_base + (w_max - w_base) * math.sin(0.5 * math.pi * t / at)
        else:
            s = (t - at) / (1.0 - at)
            w = w_max + (w_tip - w_max) * s ** 1.3
        right.append((w * 0.5, y))
        left.append((-w * 0.5, y))
    # скругление вершины
    tip = [(w_tip * 0.5 * math.cos(math.pi * k / 6), length + w_tip * tip_round * math.sin(math.pi * k / 6)) for k in range(1, 6)]
    return right + tip + list(reversed(left))


def split_leaf(pts, y_cut):
    """Делит контур листа по высоте: (низ, верх) — два многоугольника, срез горизонтальный."""
    def clip(poly, keep_below):
        out = []
        n = len(poly)
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            ina = (a[1] <= y_cut) if keep_below else (a[1] >= y_cut)
            inb = (b[1] <= y_cut) if keep_below else (b[1] >= y_cut)
            if ina:
                out.append(a)
            if ina != inb:
                t = (y_cut - a[1]) / (b[1] - a[1])
                out.append((a[0] + (b[0] - a[0]) * t, y_cut))
        return out
    return clip(pts, True), clip(pts, False)


def text_mesh(name, body, size, mat, depth=0.004):
    """Текст (шрифт Blender по умолчанию) → меш в координатах Godot: лежит в плоскости XY по центру, лицо в +Z."""
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.resolution_u = 3
    cu.extrude = depth * 0.5
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    # шрифт лежит в XY Blender-объекта с толщиной по его Z — это и есть «Godot-координаты» нашей детали
    return bm


def bm_to_obj(name, bm, mat, xf=None, wrap_r=None):
    """bmesh в координатах Godot → объект; wrap_r — «наклеить» на сферу радиуса wrap_r вокруг нуля (после xf)."""
    if xf is not None:
        bmesh.ops.transform(bm, matrix=xf, verts=bm.verts)
    if wrap_r is not None:
        for vt in bm.verts:
            p = vt.co
            ln = p.length
            vt.co = p.normalized() * (wrap_r + (ln - wrap_r))
    return K._obj(name, bm, mat)


def decal_on_sphere(name, bm, mat, center_dir, up_hint, lift=0.0015, depth=0.004):
    """Плоский рисунок (bmesh в XY, лицо +Z, толщина по Z) → облегает сферу R в направлении center_dir."""
    n = Vector(center_dir).normalized()
    x = Vector(up_hint).cross(n).normalized()
    y = n.cross(x).normalized()
    for vt in bm.verts:
        px, py, pz = vt.co
        d = (n * math.sqrt(max(R * R - px * px - py * py, 1e-6)) + x * px + y * py).normalized()
        vt.co = d * (R + SHELL_T * 0.5 + lift + (pz + depth * 0.5))
    return K._obj(name, bm, mat)


def crown_pts(w, h):
    """Корона-эмблема: основание-лента и три зубца."""
    return [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h * 0.45), (w * 0.36, h * 0.95), (w * 0.2, h * 0.5), (0.0, h),
            (-w * 0.2, h * 0.5), (-w * 0.36, h * 0.95), (-w / 2, h * 0.45)]


def poly_bm(pts, depth):
    bm = bmesh.new()
    front = [bm.verts.new((x, y, depth * 0.5)) for x, y in pts]
    back = [bm.verts.new((x, y, -depth * 0.5)) for x, y in pts]
    for (i, j, k) in K.earclip(pts):
        bm.faces.new((front[i], front[j], front[k]))
        bm.faces.new((back[k], back[j], back[i]))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    return bm


def build_body():
    parts = []
    # тёмное ядро под панелями: видно в щелях
    parts.append(patch("Core", "N0_Mech", SCREEN_TH - 4.0, 180.0, 0, 360, r_in=R - SHELL_T * 1.6, r_out=R - SHELL_T * 0.55,
                       closed=True, nph=48))
    zc0 = R * math.cos(math.radians(SCREEN_TH))
    parts.append(revolve("ScreenBack", [(R * math.sin(math.radians(SCREEN_TH)) + 0.004, zc0 - 0.03), (0.0, zc0 - 0.03)], "N0_Joint",
                         48, align_y((0, 0, 1))))
    g = GAP
    t0 = SCREEN_TH + 1.0          # передний край кольца вокруг экрана
    t1 = 60.0                     # граница кольца и боковых панелей
    t2 = 132.0                    # граница боковых панелей и спинки
    parts.append(patch("Ring_Front", "N0_Livery", t0, t1 - g * 0.5, 0, 360, closed=True, nph=72))
    # верх: две кремовые панели и жёлтая полоса по центру
    parts.append(patch("Top_R", "N0_Livery", t1 + g * 0.5, t2 - g * 0.5, 18 + g, 82 - g * 0.5))
    parts.append(patch("Top_Stripe", "N0_Accent", t1 + g * 0.5, t2 - g * 0.5, 82 + g * 0.5, 98 - g * 0.5))
    parts.append(patch("Top_L", "N0_Livery", t1 + g * 0.5, t2 - g * 0.5, 98 + g * 0.5, 162 - g))
    # бока: тёмные ленты механики (в них объективы)
    parts.append(patch("Side_R", "N0_Mech", t1 + g * 0.5, t2 - g * 0.5, -18 + g * 0.5, 18 - g * 0.5, r_out=R + SHELL_T * 0.3))
    parts.append(patch("Side_L", "N0_Mech", t1 + g * 0.5, t2 - g * 0.5, 162 + g * 0.5, 198 - g * 0.5, r_out=R + SHELL_T * 0.3))
    # низ: две кремовые панели, между ними тёмный киль двигателя
    parts.append(patch("Bot_L", "N0_Livery", t1 + g * 0.5, t2 - g * 0.5, 198 + g, 258 - g * 0.5))
    parts.append(patch("Bot_R", "N0_Livery", t1 + g * 0.5, t2 - g * 0.5, 282 + g * 0.5, 342 - g))
    parts.append(patch("Keel", "N0_Mech", t1 + g * 0.5, t2 - g * 0.5, 258 + g * 0.5, 282 - g * 0.5, r_out=R + SHELL_T * 0.3))
    # спинка — жёлтая, с гербом
    parts.append(patch("Back", "N0_Accent", t2 + g * 0.5, 180.0, 0, 360, closed=True, nph=72))

    # обойма экрана: толстое тёмное кольцо, выступает вперёд
    zc = R * math.cos(math.radians(SCREEN_TH))
    rc = R * math.sin(math.radians(SCREEN_TH))
    bez = revolve("Bezel", [(rc + 0.018, zc - 0.03), (rc + 0.024, zc + 0.004), (rc + 0.018, zc + 0.03), (rc - 0.004, zc + 0.036),
                            (rc - 0.016, zc + 0.022), (rc - 0.018, zc - 0.03)], "N0_Mech", segs=64, closed=True,
                  xf=align_y((0, 0, 1)))
    parts.append(fin(bez, 0.004, 2, angle=45))
    # заклёпки по обойме
    for k in range(16):
        a = 2 * math.pi * (k + 0.5) / 16
        p = Vector((math.cos(a) * (rc + 0.011), math.sin(a) * (rc + 0.011), zc + 0.034))
        parts.append(K.stud("Bolt_%d" % k, p, (0, 0, 1), "N0_Joint", r=0.006, h=0.004, sides=6))

    # боковые объективы (main camera 360° / боковые «уши»)
    for side, ph in (("R", 0.0), ("L", 180.0)):
        d = sdir(94.0, ph)
        base = d * (R - 0.01)
        xf = align_y(d, base)
        parts.append(fin(revolve("LensHousing_" + side, [(0.088, 0.0), (0.09, 0.03), (0.082, 0.05), (0.066, 0.056), (0.058, 0.05),
                                                         (0.0, 0.05)], "N0_Mech", segs=40, xf=xf), 0.003, 2))
        parts.append(fin(revolve("LensRing_" + side, [(0.074, 0.05), (0.075, 0.064), (0.06, 0.068), (0.052, 0.062), (0.05, 0.05)],
                                 "N0_Joint", segs=40, closed=True, xf=xf), 0.0, angle=50))
        parts.append(revolve("Lens_" + side, [(0.05, 0.05), (0.046, 0.066), (0.03, 0.074), (0.0, 0.077)], "N0_Lens", segs=32, xf=xf))
        # диафрагма объектива: тёмное кольцо и светящийся зрачок
        parts.append(revolve("Iris_" + side, [(0.026, 0.0745), (0.029, 0.077), (0.018, 0.0785), (0.014, 0.0772)], "N0_Joint", 24,
                             xf=xf, closed=True))
        parts.append(revolve("Pupil_" + side, [(0.012, 0.0768), (0.0, 0.0795)], "N0_Glow", 16, xf=xf))
        for k in range(6):
            a = 2 * math.pi * k / 6
            lp = base + xf.to_3x3() @ Vector((math.cos(a) * 0.08, 0.052, math.sin(a) * 0.08))
            parts.append(K.stud("LensBolt_%s%d" % (side, k), lp, d, "N0_Joint", r=0.005, h=0.004, sides=6))

    # антенны: две тонкие, из-за ушей, с шариками
    for side, sx in (("R", 1.0), ("L", -1.0)):
        root = sdir(112.0, 90.0 - sx * 9.0) * R
        tip = root + Vector((sx * 0.05, 0.27, -0.06))
        parts.append(revolve("AntennaBase_" + side, [(0.018, -0.01), (0.018, 0.02), (0.012, 0.03), (0.0, 0.032)], "N0_Mech", 12,
                             align_y((root - Vector((0, 0, 0))).normalized(), root)))
        parts.append(sweep("Antenna_" + side, [root, root.lerp(tip, 0.5) + Vector((0, 0.01, 0)), tip], [0.006, 0.005, 0.004],
                           "N0_Joint", sides=8))
        parts.append(sphere("AntennaTip_" + side, 0.011, tuple(tip), "N0_Accent", segs=12, rings=6))

    # двигатель-стабилизатор снизу
    bot = Vector((0, -R + 0.01, 0))
    down = align_y((0, -1, 0), bot)
    parts.append(fin(revolve("Thruster", [(0.13, -0.01), (0.135, 0.02), (0.125, 0.045), (0.105, 0.07), (0.09, 0.075), (0.075, 0.06),
                                          (0.0, 0.06)], "N0_Mech", segs=48, xf=down), 0.004, 2))
    parts.append(revolve("ThrusterGlow", [(0.072, 0.061), (0.06, 0.064), (0.0, 0.066)], "N0_Glow", segs=32, xf=down))
    parts.append(fin(torus("StabRing", (0, -R + 0.03, 0), 0.155, 0.012, "N0_Joint", plane='XZ', segs=48, sides=10), 0.0, angle=60))
    for k in range(8):
        a = 2 * math.pi * k / 8
        parts.append(box("Vent_%d" % k, (0.03, 0.012, 0.012), "N0_Joint", xf=T((math.cos(a) * 0.118, -R - 0.03, math.sin(a) * 0.118))
                         @ Matrix.Rotation(-a, 4, 'Y')))

    # спина: корона и «N0» печатью по поверхности
    back_dir = Vector((0, 0.12, -1.0))
    up = Vector((0, 1, 0))
    crown = poly_bm(crown_pts(0.12, 0.07), 0.004)
    bmesh.ops.translate(crown, vec=Vector((0, 0.035, 0)), verts=crown.verts)
    parts.append(decal_on_sphere("Crown", crown, "N0_Print", back_dir, up))
    txt = text_mesh("N0_Text", "N0", 0.13, "N0_Print")
    bmesh.ops.translate(txt, vec=Vector((0, -0.055, 0)), verts=txt.verts)
    parts.append(decal_on_sphere("BackText", txt, "N0_Print", back_dir, up))
    # номер на боку «07» — след старой маркировки под ливреей (едва заметно, тем же цветом чуть темнее — пока нет)
    return parts


def build_screen():
    """Экран-лицо: выпуклое стекло в обойме, UV — плоская проекция [0..1] (ячейка атласа)."""
    zc = R * math.cos(math.radians(SCREEN_TH))
    rs = R * math.sin(math.radians(SCREEN_TH)) - 0.012
    prof = [(rs, zc - 0.012)] + [(rs * math.cos(0.5 * math.pi * k / 8.0), zc + 0.004 + 0.03 * math.sin(0.5 * math.pi * k / 8.0))
                                 for k in range(0, 8)] + [(0.0, zc + 0.034)]
    o = revolve("N0_Screen", prof, "N0_Screen", segs=64, xf=align_y((0, 0, 1)))
    for p in o.data.polygons:
        p.use_smooth = True
    # UV: проекция на плоскость экрана (Blender X, Z = Godot X, Y), квадрат 2·rs → [0..1]
    me = o.data
    uvl = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uvl.data[loop.index].uv = (0.5 + co.x / (2 * rs), 0.5 + co.z / (2 * rs))
    return o


def build_ear(side):
    """Ухо-плавник: кремовый низ, жёлтая вершина, второй плавник позади, тёмный шарнир. Origin — шарнир."""
    sx = 1.0 if side == "R" else -1.0
    root = sdir(100.0, 90.0 - sx * 30.0) * (R + 0.005)
    xf = T(root) @ Rz(-sx * 22.0) @ Rx(-24.0) @ Matrix.Rotation(math.radians(sx * 28.0), 4, 'Y')
    pts = leaf(14, 0.5, 0.12, 0.175, 0.06, at=0.35)
    lo, hi = split_leaf(pts, 0.31)
    lo_o = extrude2d("Ear_%s_Lo" % side, lo, -0.014, 0.014, "N0_Livery", bend=1.6, xf=xf @ T((0, 0.02, 0)))
    hi_o = extrude2d("Ear_%s_Hi" % side, [(x, y + 0.006) for x, y in hi], -0.014, 0.014, "N0_Accent", bend=1.6, xf=xf @ T((0, 0.02, 0)))
    # второй плавник: меньше, позади и шире наружу
    xf2 = T(root + Vector((sx * 0.02, -0.02, -0.07))) @ Rz(-sx * 36.0) @ Rx(-38.0) @ Matrix.Rotation(math.radians(sx * 34.0), 4, 'Y')
    pts2 = leaf(12, 0.32, 0.08, 0.11, 0.045, at=0.4)
    lo2, hi2 = split_leaf(pts2, 0.22)
    back_lo = extrude2d("Ear_%s_BackLo" % side, lo2, -0.011, 0.011, "N0_Livery", bend=1.8, xf=xf2)
    back_hi = extrude2d("Ear_%s_BackHi" % side, [(x, y + 0.005) for x, y in hi2], -0.011, 0.011, "N0_Accent", bend=1.8, xf=xf2)
    objs = [fin(o, 0.004, 2, angle=45) for o in (lo_o, hi_o, back_lo, back_hi)]
    # шарнир у основания
    hinge_axis = (xf.to_3x3() @ Vector((1, 0, 0))).normalized()
    objs.append(fin(revolve("Ear_%s_Hinge" % side, [(0.034, -0.05), (0.036, -0.04), (0.036, 0.04), (0.034, 0.05), (0.0, 0.05)],
                            "N0_Mech", 20, align_y(hinge_axis, root + hinge_axis * 0.0)), 0.003, 2))
    o = C.join(objs, "N0_Ear_" + side)
    C.set_origin(o, G2B @ root)
    return o


def build_legs(side):
    """Две изогнутые пластины-«ножки» на шарнире под корпусом. Origin — шарнир."""
    sx = 1.0 if side == "R" else -1.0
    root = sdir(116.0, 270.0 + sx * 38.0) * (R - 0.005)
    objs = [fin(sphere("Legs_%s_Ball" % side, 0.042, tuple(root), "N0_Joint", 20, 10), 0.0, angle=60)]
    for k, (ln, spread, back, w) in enumerate(((0.36, 8.0, 0.0, 0.085), (0.28, 22.0, -16.0, 0.07))):
        xf = T(root) @ Rz(180.0 + sx * spread) @ Rx(back) @ Matrix.Rotation(math.radians(sx * 35.0), 4, 'Y')
        pts = leaf(12, ln, w * 0.7, w, w * 0.45, at=0.3)
        lo, hi = split_leaf(pts, ln * 0.78)
        objs.append(fin(extrude2d("Legs_%s_%d_Lo" % (side, k), lo, -0.012, 0.012, "N0_Livery", bend=2.2, xf=xf @ T((0, 0.03, 0))), 0.004, 2))
        objs.append(fin(extrude2d("Legs_%s_%d_Hi" % (side, k), [(x, y + 0.005) for x, y in hi], -0.012, 0.012, "N0_Accent", bend=2.2,
                                  xf=xf @ T((0, 0.03, 0))), 0.004, 2))
        # тёмная тяга-кронштейн пластины
        objs.append(sweep("Legs_%s_%d_Rod" % (side, k), [root, root + xf.to_3x3() @ Vector((0, 0.08, 0))], 0.012, "N0_Mech", sides=10))
    o = C.join(objs, "N0_Legs_" + side)
    C.set_origin(o, G2B @ root)
    return o


def arm_chain(name, pts, radius, claw=True):
    """Рука-манипулятор: сегменты-трубы, шары суставов, на конце клешня из двух пальцев."""
    objs = []
    for i, p in enumerate(pts):
        objs.append(fin(sphere("%s_J%d" % (name, i), radius * 1.55, tuple(p), "N0_Joint", 16, 8), 0.0, angle=60))
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        objs.append(fin(sweep("%s_S%d" % (name, i), [a, b], radius, "N0_Mech", sides=12), 0.0, angle=50))
        # кремовая накладка на сегмент (как на листе «utility arm»)
        mid = a.lerp(b, 0.5)
        d = (b - a).normalized()
        objs.append(fin(revolve("%s_P%d" % (name, i), [(radius * 1.25, -0.035), (radius * 1.45, -0.02), (radius * 1.45, 0.02),
                                                       (radius * 1.25, 0.035)], "N0_Livery", 12, align_y(d, mid), closed=True), 0.0))
    if claw:
        a, b = pts[-2], pts[-1]
        d = (b - a).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        for s in (1.0, -1.0):
            f0 = b + side * s * radius * 1.2
            objs.append(sweep("%s_F%d" % (name, int(s > 0)), [f0, f0 + d * 0.035 + side * s * 0.012, f0 + d * 0.06 - side * s * 0.004],
                              [radius * 0.8, radius * 0.7, radius * 0.4], "N0_Mech", sides=8))
    return objs


def build_arms():
    # правая рука (к камере справа, +X) держит микрофон перед собой
    sh_r = sdir(104.0, 332.0) * (R - 0.01)
    mic_grip = Vector((0.40, -0.16, 0.20))
    pr = [sh_r, sh_r + Vector((0.07, -0.10, 0.02)), sh_r + Vector((0.12, -0.08, 0.13)), mic_grip]
    arm_r = C.join(arm_chain("ArmR", pr, 0.013), "N0_Arm_R")
    C.set_origin(arm_r, G2B @ sh_r)
    # левая рука-инструмент сложена вдоль корпуса
    sh_l = sdir(104.0, 208.0) * (R - 0.01)
    pl = [sh_l, sh_l + Vector((-0.08, -0.08, 0.03)), sh_l + Vector((-0.06, -0.17, 0.10)), sh_l + Vector((-0.02, -0.19, 0.16))]
    arm_l = C.join(arm_chain("ArmL", pl, 0.012), "N0_Arm_L")
    C.set_origin(arm_l, G2B @ sh_l)
    return arm_r, arm_l, mic_grip


def build_mic(grip):
    """Ручной микрофон: рукоять, кубик-флажок «N0», сетчатая голова (поролон). Origin — хват."""
    up = Vector((0.15, 1.0, 0.35)).normalized()
    xf = align_y(up, grip)
    objs = [fin(revolve("Mic_Handle", [(0.013, -0.05), (0.016, -0.04), (0.019, 0.06), (0.024, 0.09), (0.024, 0.1), (0.0, 0.1)],
                        "N0_Joint", 16, xf), 0.002, 1),
            fin(revolve("Mic_Grille", [(0.024, 0.098), (0.036, 0.112), (0.041, 0.13), (0.036, 0.15), (0.02, 0.162), (0.0, 0.166)],
                        "N0_Rubber", 20, xf), 0.0, angle=60)]
    cube_c = grip + up * 0.075
    rot = xf.to_3x3().to_4x4()
    objs.append(fin(box("Mic_Flag", (0.062, 0.05, 0.062), "N0_Flag", xf=T(cube_c) @ rot), 0.004, 2))
    for k in range(4):   # «N0» на четырёх гранях кубика
        a = math.radians(90.0 * k)
        face_rot = rot @ Matrix.Rotation(a, 4, 'Y')
        bm = text_mesh("MicTxt_%d" % k, "N0", 0.032, "N0_Print")
        o = bm_to_obj("Mic_Txt_%d" % k, bm, "N0_Print", xf=T(cube_c) @ face_rot @ T((0, -0.002, 0.0312)))
        objs.append(o)
    o = C.join(objs, "N0_Mic")
    C.set_origin(o, G2B @ grip)
    return o


def build_all(livery="default", export=False, face=0):
    C.reset_scene()
    K._MATS.clear()
    if not os.path.exists(ATLAS_PNG) or export:
        make_face_atlas(ATLAS_PNG)
    setup_materials(livery, export, face)
    body = C.join(build_body(), "N0_Body")
    C.set_origin(body, (0.0, 0.0, 0.0))
    screen = build_screen()
    ears = [build_ear("L"), build_ear("R")]
    legs = [build_legs("L"), build_legs("R")]
    arm_r, arm_l, grip = build_arms()
    mic = build_mic(grip)
    objs = [body, screen] + ears + legs + [arm_r, arm_l, mic]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    print("N0: %d objects, %d tris, size (Godot x/y/z) %.3f × %.3f × %.3f m" % (len(objs), tris, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y))
    return objs, tris


# ----------------------------------------------------------------------------------------------------------------------
# превью: 4 вида в ряд, как разворот на листе
# ----------------------------------------------------------------------------------------------------------------------
def render_preview(out_png, livery="default", face=0, samples=24, views=(0.0, 35.0, 90.0, 180.0), height=820):
    objs, _ = build_all(livery, False, face)
    res = (int(height * 0.73 * len(views)) + 60, height)
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    scn.cycles.device = 'CPU'
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.image_settings.file_format = 'PNG'
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new("World")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.05, 0.055, 0.07, 1.0)
    bg.inputs['Strength'].default_value = 1.0
    for nm, col, energy, rot in (("Key", (1.0, 0.82, 0.62), 3.2, (math.radians(50), 0, math.radians(-30))),
                                 ("Rim", (0.45, 0.6, 1.0), 2.4, (math.radians(70), 0, math.radians(160))),
                                 ("Fill", (1.0, 0.95, 0.9), 0.8, (math.radians(80), 0, math.radians(60)))):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.color = col
        ld.energy = energy
        ld.angle = math.radians(8.0)
        lo = bpy.data.objects.new(nm, ld)
        scn.collection.objects.link(lo)
        lo.rotation_euler = rot
    # 4 копии: поворот вокруг вертикали (Blender Z): front, 3/4, side, back
    root = bpy.data.objects.new("N0_Root", None)
    scn.collection.objects.link(root)
    for o in objs:
        o.parent = root
    spacing = 1.25
    holders = []
    for i, yaw in enumerate(views):
        if i == 0:
            h = root
        else:
            h = bpy.data.objects.new("N0_Copy%d" % i, None)
            scn.collection.objects.link(h)
            for o in objs:
                c = o.copy()
                scn.collection.objects.link(c)
                c.parent = h
                c.matrix_parent_inverse = o.matrix_parent_inverse.copy()
        h.location = ((i - (len(views) - 1) * 0.5) * spacing, 0.0, 0.0)
        h.rotation_euler = (0.0, 0.0, math.radians(yaw))
        holders.append(h)
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = spacing * len(views) * 1.02
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    cam.location = (0.0, -20.0, 0.14)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    cam_d.clip_end = 100.0
    scn.camera = cam
    scn.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("preview →", out_png)


def export_glb(livery="default"):
    objs, tris = build_all(livery, True, 0)
    path = os.path.join(OUT_DIR, "n0.glb")
    C.export_glb(path, objs)
    print("=== n0 === tris %d, %s (%d B)" % (tris, path, os.path.getsize(path)))
    if tris > TRI_BUDGET:
        print("ERROR: over budget", tris, ">", TRI_BUDGET)
        sys.exit(1)


if __name__ == "__main__":
    args = C.args_after_dashdash()
    livery = args[args.index("--livery") + 1] if "--livery" in args else "default"
    face = int(args[args.index("--face") + 1]) if "--face" in args else 0
    if "--export" in args:
        export_glb(livery)
    elif "--preview" in args:
        views = [float(x) for x in args[args.index("--views") + 1].split(",")] if "--views" in args else (0.0, 35.0, 90.0, 180.0)
        render_preview(args[args.index("--preview") + 1], livery, face,
                       samples=int(args[args.index("--samples") + 1]) if "--samples" in args else 24, views=views,
                       height=int(args[args.index("--height") + 1]) if "--height" in args else 820)
