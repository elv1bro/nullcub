"""Руки героя от первого лица для гаража (06.10, автор: «а можно руки красивее сделать?»; сцена — scenes/menu/fp_hands.gd).

Правая рука механика: рукав рабочей куртки (тёмно-синий, манжета-резинка, светоотражающая полоса), перчатка без пальцев (тыльная
сторона — ткань, ладонь — кожа, оранжевая накладка на костяшках и липучка на запястье), кожа на средних и концевых фалангах,
ногти. Левая рука — та же сборка, отражённая по X при построении (FP_Hand_L.glb): отрицательный масштаб в игре портит нормали.

Каждая фаланга — отдельный объект с началом в своём суставе, вложенный в предыдущую: Godot сгибает их поворотом узла вокруг
локальной X (пальцы) — скелет и анимации не нужны. Иерархия (имена узлов читает fp_hands.gd):
  Arm (рукав, начало — запястье) → Hand (ладонь, перчатка) → F1_1 → F1_2 → F1_3 (указательный) … F4_* (мизинец), T_1 → T_2 → T_3
  (большой).
Оси Blender: X вбок (большой палец правой — в −X), Y — вперёд (пальцы), Z — тыльная сторона; после экспорта: пальцы → −Z Godot,
тыл → +Y, рукав уходит в +Z (к локтю).

Формы — «лофты»: кольца-сечения (скруглённые прямоугольники и эллипсы) вдоль оси, торцы — купола; гладкое затенение. Материалы
плоские (цвета Principled), Godot берёт их из glb как есть.

Запуск: blender -b --python godot/tools/blender/fp_hands.py [-- --preview /abs/out.png]
  → godot/assets/models/hands/FP_Hand_R.glb и FP_Hand_L.glb (+ превью правой рендером Workbench при --preview)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

OUT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "models", "hands"))
MIRROR = False          # левая рука: геометрия отражена по X (честная модель, без отрицательного масштаба в игре)

PALM_LEN = 0.092
# пальцы: x корня на линии костяшек, длины фаланг, радиус у корня, наклон в сторону (градусы, + к мизинцу)
FINGERS = [
    ("F1", -0.0285, [0.042, 0.025, 0.021], 0.0098, -4.0),
    ("F2", -0.0095, [0.046, 0.029, 0.022], 0.0102, -1.0),
    ("F3", 0.0098, [0.044, 0.027, 0.021], 0.0097, 2.5),
    ("F4", 0.028, [0.034, 0.021, 0.018], 0.0086, 6.0),
]
MATS = {
    "Sleeve": dict(base=(0.11, 0.15, 0.25, 1.0), rough=0.92),
    "SleeveRib": dict(base=(0.07, 0.08, 0.11, 1.0), rough=0.95),
    "Reflect": dict(base=(0.72, 0.74, 0.72, 1.0), rough=0.3, metal=0.35),
    "GloveFabric": dict(base=(0.1, 0.1, 0.11, 1.0), rough=0.88),
    "GloveLeather": dict(base=(0.46, 0.31, 0.19, 1.0), rough=0.58),
    "GlovePad": dict(base=(0.9, 0.42, 0.12, 1.0), rough=0.55),
    "Skin": dict(base=(0.8, 0.57, 0.45, 1.0), rough=0.5),
    "Nail": dict(base=(0.88, 0.72, 0.66, 1.0), rough=0.3),
}


def _lin(c):
    """Цвета MATS — как на экране (sRGB); Principled и glTF ждут линейные (Godot переводит обратно в sRGB при импорте)."""
    return tuple((v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c[:3]) + (c[3],)


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        spec = dict(MATS[name])
        spec["base"] = _lin(spec["base"])
        m = C.material(name, **spec)
        m.diffuse_color = spec["base"]     # цвет в превью Workbench
    return m


# ---------------------------------------------------------------- лофты

def ring_rrect(w, t, n=20, p=2.6, zc=0.0, arch=0.0):
    """Сечение-суперэллипс в плоскости XZ: ширина w, толщина t, показатель p (2 — эллипс, больше — квадратнее); arch — выпуклость
    тыла (верх приподнят в середине)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / p), c) * w * 0.5
        z = math.copysign(abs(s) ** (2.0 / p), s) * t * 0.5
        if z > 0:
            z += arch * (1.0 - (2.0 * x / w) ** 2)
        pts.append((x, z + zc))
    return pts


def loft(bm, sections, cap0=True, cap1=True, dome=0.6):
    """sections — [(y, [(x, z)…]), …] с одинаковым числом точек; торцы — купола (вершина на оси, вынесена на dome × радиус)."""
    rings = []
    for y, pts in sections:
        rings.append([bm.verts.new((x, y, z)) for x, z in pts])
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            m = (k + 1) % n
            bm.faces.new((a[k], a[m], b[m], b[k]))
    for ring, y, sign, on in ((rings[0], sections[0][0], -1.0, cap0), (rings[-1], sections[-1][0], 1.0, cap1)):
        if not on:
            continue
        cx = sum(v.co.x for v in ring) / n
        cz = sum(v.co.z for v in ring) / n
        r = sum((Vector((v.co.x - cx, 0, v.co.z - cz))).length for v in ring) / n
        mid = [bm.verts.new((cx + (v.co.x - cx) * 0.62, y + sign * r * dome * 0.62, cz + (v.co.z - cz) * 0.62)) for v in ring]
        tip = bm.verts.new((cx, y + sign * r * dome, cz))
        for k in range(n):
            m = (k + 1) % n
            bm.faces.new((ring[k], ring[m], mid[m], mid[k]) if sign > 0 else (ring[m], ring[k], mid[k], mid[m]))
            bm.faces.new((mid[k], mid[m], tip) if sign > 0 else (mid[m], mid[k], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def mesh_obj(name, bm, material, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), split=None):
    """Объект из bmesh: гладкое затенение; split(face) → имя материала для части граней (двухцветная перчатка)."""
    if MIRROR:
        for v in bm.verts:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        loc = (-loc[0], loc[1], loc[2])
        rot = (rot[0], -rot[1], -rot[2])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(mat(material))
    if split is not None:
        names = [material]
        for p in me.polygons:
            m = split(p)
            if m and m not in names:
                names.append(m)
                me.materials.append(mat(m))
            p.material_index = names.index(m) if m else 0
    if parent is not None:
        ob.parent = parent
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    return ob


def tube(r0, r1, length, n=14, squash=1.0, y0=0.0, cap0=True, cap1=True, dome=0.8, bulges=()):
    """Сужающаяся «капсула» вдоль +Y от y0: радиус r0 → r1, сечение — эллипс (высота × squash), bulges — [(доля, +радиус)]."""
    bm = bmesh.new()
    secs = []
    steps = 6 + 2 * len(bulges)
    for i in range(steps + 1):
        u = i / steps
        r = r0 + (r1 - r0) * u
        for f, dr in bulges:
            r += dr * math.exp(-((u - f) / 0.06) ** 2)
        secs.append((y0 + length * u, [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r * squash) for k in range(n)]))
    loft(bm, secs, cap0, cap1, dome)
    return bm


# ---------------------------------------------------------------- детали

def build_arm():
    """Рукав: от запястья к локтю (−Y), манжета-резинка у запястья, светоотражающая полоса, лёгкие складки. Конец за кадром."""
    bm = tube(0.06, 0.044, 0.56, n=18, squash=0.92, y0=-0.585, cap0=True, cap1=False, bulges=((0.35, 0.003), (0.55, 0.0025), (0.7, 0.002)))
    arm = mesh_obj("Arm", bm, "Sleeve")
    rib = tube(0.0455, 0.0445, 0.045, n=18, squash=0.92, y0=-0.07, cap0=False, cap1=False)
    mesh_obj("Arm_Rib", rib, "SleeveRib", arm)
    stripe = tube(0.0505, 0.0495, 0.022, n=18, squash=0.92, y0=-0.2, cap0=False, cap1=False)
    mesh_obj("Arm_Stripe", stripe, "Reflect", arm)
    return arm


def build_hand(arm):
    """Ладонь в перчатке: лофт от запястья к костяшкам (тыл чуть выпуклый), низ — кожа ладони, верх — ткань; манжета перчатки
    с липучкой, накладка на костяшках."""
    bm = bmesh.new()
    secs = [(-0.03, ring_rrect(0.062, 0.04, p=2.2)), (-0.005, ring_rrect(0.066, 0.036, p=2.3)), (0.02, ring_rrect(0.074, 0.033, p=2.6, arch=0.002)),
            (0.05, ring_rrect(0.083, 0.031, p=2.9, arch=0.003)), (0.075, ring_rrect(0.087, 0.029, p=3.0, arch=0.003)),
            (PALM_LEN, ring_rrect(0.086, 0.025, p=2.8, arch=0.002))]
    loft(bm, secs, cap0=False, cap1=True, dome=0.45)
    hand = mesh_obj("Hand", bm, "GloveFabric", arm, split=lambda p: "GloveLeather" if p.normal.z < -0.35 else None)
    # бугор большого пальца (ладонная сторона, у основания большого)
    th = bmesh.new()
    bmesh.ops.create_uvsphere(th, u_segments=16, v_segments=10, radius=1.0)
    bmesh.ops.scale(th, vec=(0.02, 0.03, 0.013), verts=th.verts)
    mesh_obj("Hand_Thenar", th, "GloveLeather", hand, loc=(-0.022, 0.03, -0.01))
    # манжета перчатки и липучка
    cuff = tube(0.039, 0.035, 0.05, n=18, squash=0.86, y0=-0.045, cap0=False, cap1=False)
    mesh_obj("Hand_Cuff", cuff, "GloveFabric", hand)
    strap = bmesh.new()
    loft(strap, [(y, ring_rrect(0.084, 0.072, n=20, p=3.2)) for y in (-0.034, -0.012)], cap0=False, cap1=False)
    mesh_obj("Hand_Strap", strap, "GlovePad", hand)
    # накладка на костяшках: скруглённая пластина поверх тыла
    pad = bmesh.new()
    loft(pad, [(y, ring_rrect(w, 0.006, n=16, p=3.4, arch=0.003)) for y, w in ((0.056, 0.068), (0.071, 0.078), (0.087, 0.077))], dome=0.9)
    mesh_obj("Hand_Pad", pad, "GlovePad", hand, loc=(0, 0, 0.0158))
    return hand


def build_finger(hand, name, x, lens, r, splay):
    """Палец: три фаланги-капсулы; первая — в перчатке (ткань, подвёрнутый край), вторая и третья — кожа, на третьей ноготь."""
    parent = hand
    loc = (x, PALM_LEN - 0.006, 0.0)
    rot = (0, 0, -splay)
    objs = []
    for k, L in enumerate(lens):
        r0 = r * (1.0 - 0.09 * k)
        r1 = r0 * (0.9 if k < 2 else 0.78)
        bm = tube(r0, r1, L, n=12, squash=0.86, cap0=True, cap1=True, dome=0.75 if k < 2 else 1.0)
        material = "GloveFabric" if k == 0 else "Skin"
        ob = mesh_obj("%s_%d" % (name, k + 1), bm, material, parent, loc, rot)
        if k == 0:   # подвёрнутый край перчатки
            edge = tube(r1 * 1.12, r1 * 1.1, 0.007, n=12, squash=0.86, y0=L - 0.008, cap0=False, cap1=False)
            mesh_obj("%s_Edge" % name, edge, "GloveFabric", ob)
        if k == 2:   # ноготь — тонкая пластина на тыле концевой фаланги
            nail = bmesh.new()
            loft(nail, [(y, ring_rrect(w, 0.0024, n=12, p=2.4)) for y, w in ((L * 0.35, r1 * 1.4), (L * 0.75, r1 * 1.55), (L * 0.98, r1 * 1.3))], dome=0.4)
            mesh_obj("%s_Nail" % name, nail, "Nail", ob, loc=(0, 0, r1 * 0.78))
        objs.append(ob)
        parent = ob
        loc = (0, L, 0)
        rot = (0, 0, 0)
    return objs


def build_thumb(hand):
    """Большой палец: от основания ладони вперёд-вбок-вниз; первые две фаланги — в перчатке, концевая — кожа с ногтем."""
    t1 = mesh_obj("T_1", tube(0.0135, 0.0122, 0.04, n=12, squash=0.85, dome=0.7), "GloveFabric", hand, (-0.03, 0.018, -0.006), (-18, -35, 42))
    t2 = mesh_obj("T_2", tube(0.0122, 0.0112, 0.03, n=12, squash=0.85, dome=0.7), "GloveFabric", t1, (0, 0.04, 0))
    edge = tube(0.0126, 0.0124, 0.006, n=12, squash=0.85, y0=0.024, cap0=False, cap1=False)
    mesh_obj("T_Edge", edge, "GloveFabric", t2)
    t3 = mesh_obj("T_3", tube(0.011, 0.0086, 0.026, n=12, squash=0.85, dome=1.0), "Skin", t2, (0, 0.03, 0))
    nail = bmesh.new()
    loft(nail, [(y, ring_rrect(w, 0.0024, n=12, p=2.4)) for y, w in ((0.008, 0.012), (0.018, 0.0135), (0.025, 0.011))], dome=0.4)
    mesh_obj("T_Nail", nail, "Nail", t3, loc=(0, 0, 0.0082))
    return [t1, t2, t3]


def preview(path):
    """Превью Workbench с трёх сторон (сверху-сзади — как из глаз, сбоку, с ладони) — склейку делает вызывающий; пишет path_<k>.png."""
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.render.resolution_x, scn.render.resolution_y = 900, 700
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    for k, pos in enumerate([(0.12, -0.3, 0.2), (0.32, 0.06, 0.03), (0.05, 0.1, -0.3)]):
        cam.location = pos
        d = Vector((0.0, 0.07, 0.0)) - cam.location
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        scn.render.filepath = path.replace(".png", "_%d.png" % k)
        bpy.ops.render.render(write_still=True)


def build():
    arm = build_arm()
    hand = build_hand(arm)
    for f in FINGERS:
        build_finger(hand, *f)
    build_thumb(hand)
    return arm


def main():
    global MIRROR
    argv = C.args_after_dashdash()
    for side in ("R", "L"):
        MIRROR = side == "L"
        C.reset_scene()
        arm = build()
        C.export_glb(os.path.join(OUT_DIR, "FP_Hand_%s.glb" % side), [arm], apply_modifiers=True)
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in [arm] + list(arm.children_recursive))
        print("=== fp hand %s === objects %d, tris %d" % (side, 1 + len(arm.children_recursive), tris))
        if side == "R" and "--preview" in argv:
            preview(argv[argv.index("--preview") + 1])


main()
