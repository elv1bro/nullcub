"""Общее для кита тела v2 (tools/blender/body_kit.py): материалы по ролям, узлы (обоймы, заклёпки, колышки, плашка лица,
окошко Ядра), кадры якорей ядра, маркеры конечностей. Модули деталей: kit_joints, kit_heads, kit_cores, kit_limbs, kit_ends,
kit_deco, kit_weapons — в каждом функции build_<Имя>(**kw) → (объекты, маркеры[, FacePlate]).
Геометрия — в координатах Godot (craft_parts.G2B переводит в Blender), origin детали = Socket, рост в −Y."""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import craft_parts as K
from craft_parts import (G2B, B2G, TAU, T, Rz, Rx, S, align_y, revolve, sphere, box, loft, sweep, circle, torus,  # noqa: F401
                         extrude2d, stud, spike, fin, cut_box, cut_sphere, empty, socket, anchor, shape_box, shape_sphere,
                         shape_cyl, shape_capsule, superellipse, M)

MIR = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))   # зеркало по X в координатах Godot (правая сторона)

# цвета игроков — Tuning.PLAYER_COLORS (2f6fde, d9342b, 2e9e4f, e8b820), в линейном пространстве
PLAYER_LIN = [(0.028, 0.16, 0.73, 1.0), (0.69, 0.033, 0.024, 1.0), (0.027, 0.36, 0.078, 1.0), (0.81, 0.48, 0.013, 1.0)]

# материалы кита: имя → (папка PBR, kwargs textured_material, плоский запасной (цвет, шероховатость), тайлов на метр)
KIT_MATS = {
    "Base_Wood": ("wood", {"tint": (1.0, 0.92, 0.82, 1.0)}, ((0.62, 0.40, 0.20, 1.0), 0.6), 2.0),
    "Base_Maple": ("maple_light", {}, ((0.60, 0.42, 0.24, 1.0), 0.6), 2.0),
    "Base_WoodDark": ("wood_dark", {}, ((0.25, 0.14, 0.07, 1.0), 0.65), 2.0),
    "Base_Planks": ("wood_plank", {}, ((0.45, 0.28, 0.14, 1.0), 0.7), 2.0),
    # краски — НЕ цвета игроков (29.09, QA на Свалке): красная / синяя / жёлтая / зелёная краска совпадали с PLAYER_COLORS
    # (ΔE2000 3–6), и кукла P1 в красной краске читалась как P2. Теперь бордовая / бирюзовая / горчичная / оливковая —
    # ΔE2000 ≥ 23 от каждого цвета игрока (BODY_KIT.md §4); tint = цель sRGB (линейно) / среднее albedo paint_marks (~0.82)
    "Base_PaintRed": ("paint_marks", {"tint": (0.19, 0.014, 0.057, 1.0), "roughness_scale": 0.75}, ((0.19, 0.014, 0.057, 1.0), 0.45), 2.0),
    "Base_PaintBlue": ("paint_marks", {"tint": (0.016, 0.19, 0.206, 1.0), "roughness_scale": 0.75}, ((0.016, 0.19, 0.206, 1.0), 0.45), 2.0),
    "Base_PaintYellow": ("paint_marks", {"tint": (0.30, 0.176, 0.018, 1.0), "roughness_scale": 0.75}, ((0.30, 0.176, 0.018, 1.0), 0.45), 2.0),
    "Base_PaintWhite": ("paint_marks", {"tint": (0.80, 0.78, 0.72, 1.0), "roughness_scale": 0.75}, ((0.8, 0.78, 0.72, 1.0), 0.45), 2.0),
    "Base_PaintGreen": ("paint_marks", {"tint": (0.121, 0.125, 0.025, 1.0), "roughness_scale": 0.75}, ((0.121, 0.125, 0.025, 1.0), 0.45), 2.0),
    "Base_RustRed": ("rust_painted_red", {}, ((0.30, 0.05, 0.03, 1.0), 0.62), 2.0),
    # железо — тёмный крашеный / кованый металл (кадр стиля body-kit-v1.png): albedo карты iron (~0.06 линейно) поднят tint > 1,
    # металличность 0.5 вместо карты (0.9). В Godot (tools/build_body_kit.gd MATS) albedo ~0.27–0.3: на тёмном фоне отражать нечего;
    # здесь (светлый мир кадра даёт отражения) ~0.2 — на листе железо того же тона, что в игре
    "Base_Iron": ("iron", {"tint": (2.6, 3.3, 3.3, 1.0), "metallic": 0.5}, ((0.20, 0.20, 0.21, 1.0), 0.55), 2.0),
    "Base_Rust": ("rust_metal", {"tint": (1.35, 1.5, 1.6, 1.0), "metallic": 0.3}, ((0.20, 0.11, 0.06, 1.0), 0.78), 2.0),
    # латунь: металличность — константа ≈ средняя в Godot (Brass.tres / Base_Brass.tres: 0.7 × карта brass_worn ≈ 0.64);
    # без неё Blender брал карту как есть (~0.92), и на листе латунь блестела сильнее, чем в игре
    "Base_Brass": ("brass_worn", {"metallic": 0.65}, ((0.50, 0.36, 0.14, 1.0), 0.38), 2.0),
    "Base_Bone": ("paint_marks", {"tint": (0.86, 0.76, 0.56, 1.0)}, ((0.86, 0.76, 0.56, 1.0), 0.6), 2.0),
    "Base_Pink": ("paint_marks", {"tint": (0.85, 0.30, 0.42, 1.0), "roughness_scale": 0.6}, ((0.85, 0.3, 0.42, 1.0), 0.4), 2.0),
    # фурнитура (Steel / Brass / Rust / RustDark здесь перекрывают craft_parts.MAT_DEFS только для кита)
    "Iron": ("iron", {"tint": (2.4, 3.0, 3.0, 1.0), "metallic": 0.5}, ((0.17, 0.17, 0.18, 1.0), 0.55), 2.0),
    "Brass": ("brass_worn", {"metallic": 0.65}, ((0.50, 0.36, 0.14, 1.0), 0.38), 2.0),
    "Steel": ("iron", {"tint": (3.6, 4.6, 4.6, 1.0), "metallic": 0.6}, ((0.28, 0.28, 0.29, 1.0), 0.45), 2.0),
    "Rust": ("rust_metal", {"tint": (1.35, 1.5, 1.6, 1.0), "metallic": 0.3}, ((0.20, 0.11, 0.06, 1.0), 0.78), 1.5),
    "RustDark": ("rust_metal", {"tint": (0.8, 0.8, 0.85, 1.0), "metallic": 0.3}, ((0.08, 0.06, 0.05, 1.0), 0.72), 1.5),
    "Bone": ("paint_marks", {"tint": (0.86, 0.76, 0.56, 1.0)}, ((0.86, 0.76, 0.56, 1.0), 0.6), 2.0),
    "Shirt_Kit": ("paint_marks", {"tint": PLAYER_LIN[0], "roughness_scale": 0.7}, (PLAYER_LIN[0], 0.45), 2.0),
}
for _i, _c in enumerate(PLAYER_LIN):
    KIT_MATS["Shirt_P%d" % (_i + 1)] = ("paint_marks", {"tint": _c, "roughness_scale": 0.7}, (_c, 0.45), 2.0)
KIT_FLAT = {"Rubber": ((0.03, 0.028, 0.027, 1.0), 0.85, 0.0), "Screen": ((0.01, 0.012, 0.014, 1.0), 0.2, 0.0),
            "Gem": ((0.55, 0.02, 0.03, 1.0), 0.12, 0.0),
            # закопчённое стекло фонаря: янтарное, полупрозрачное (альфа GLASS_ALPHA — в kit_setup; в Godot Glass.tres, прозрачность)
            "Glass": ((0.50, 0.30, 0.10, 1.0), 0.08, 0.0)}
GLASS_ALPHA = 0.38
# эмиссия окошка Ядра в кадре (AgX): 9 выжигало купол в белое; 1.2 — тёплый оранжевый с горячей серединой (в Godot — MATS CoreGlow)
CORE_GLOW_STRENGTH = 1.2
BASES = ["Wood", "Maple", "WoodDark", "Planks", "PaintRed", "PaintBlue", "PaintYellow", "PaintWhite", "PaintGreen", "RustRed",
         "Iron", "Rust", "Brass", "Bone", "Pink"]

# радиусы шаров шарниров по якорю (как «шары» куклы v3, чуть крупнее — игрушка)
JOINT_R = {"Neck": 0.05, "Shoulder": 0.064, "Elbow": 0.054, "Wrist": 0.044, "Hip": 0.076, "Knee": 0.066, "Ankle": 0.052,
           "Side": 0.062, "End": 0.052, "Top": 0.0, "Deco": 0.0, "Back": 0.0, "SideB": 0.062}


def kit_setup(export=False):
    """Регистрирует материалы кита в craft_parts (M() берёт их оттуда) и особые материалы (лицо, свечение Ядра).
    export=True — для glb: все материалы плоские (имя = роль; настоящие материалы назначает Godot-builder), лицо без картинки."""
    K.MAT_DEFS.update(KIT_MATS)
    K.FLAT.update(KIT_FLAT)
    K.FORCE_FLAT = export
    # тёмная база, насыщенная эмиссия: подсветка сцены не разбавляет оранжевый до белого (как CoreGlow в Godot)
    K._MATS["CoreGlow"] = C.material("CoreGlow", (0.30, 0.10, 0.02, 1.0), 0.3, 0.0, emission=(1.0, 0.25, 0.03, 1.0),
                                     emission_strength=CORE_GLOW_STRENGTH)
    K._MATS["Face"] = C.material("Face", (0.80, 0.62, 0.42, 1.0), 0.55, 0.0) if export else face_material()
    if not export:   # в glb стекло плоское (имя = роль), прозрачность ставит Godot (Glass.tres)
        glass = K.M("Glass")
        gb = glass.node_tree.nodes.get("Principled BSDF")
        gb.inputs["Alpha"].default_value = GLASS_ALPHA
        gb.inputs["Emission Color"].default_value = (1.0, 0.55, 0.2, 1.0)   # слабый отсвет огарка (Glass.tres: glow, energy 0.2)
        gb.inputs["Emission Strength"].default_value = 0.3
        if hasattr(glass, "surface_render_method"):   # EEVEE (Blender 4.2+); Cycles берёт Alpha из BSDF сам
            glass.surface_render_method = 'BLENDED'


def face_material():
    """Плашка лица для кадра стиля: мультяшное лицо на «фотокарточке» (в игре сюда ляжет фото игрока)."""
    name = "Face"
    img = bpy.data.images.get("kit_face")
    if img is None:
        n = 256
        img = bpy.data.images.new("kit_face", n, n, alpha=False)
        px = [0.0] * (n * n * 4)
        for j in range(n):
            v = j / (n - 1)
            for i in range(n):
                u = i / (n - 1)
                r, g, b = 0.80, 0.62, 0.42          # фотобумага, тёплая (линейные значения)
                edge = min(u, v, 1 - u, 1 - v)
                if edge < 0.035:
                    r, g, b = 0.93, 0.88, 0.78      # белая кайма карточки
                for ex in (0.32, 0.68):
                    du, dv = (u - ex) / 0.075, (v - 0.58) / 0.11
                    if du * du + dv * dv < 1.0:
                        r, g, b = 0.02, 0.02, 0.025
                        hu, hv = (u - ex + 0.022) / 0.024, (v - 0.625) / 0.03
                        if hu * hu + hv * hv < 1.0:
                            r, g, b = 0.9, 0.9, 0.9
                for cx in (0.2, 0.8):
                    du, dv = (u - cx) / 0.08, (v - 0.4) / 0.05
                    if du * du + dv * dv < 1.0:
                        r, g, b = r * 0.9 + 0.08, g * 0.7, b * 0.7
                # улыбка: дуга окружности
                d = math.hypot(u - 0.5, v - 0.47)
                if abs(d - 0.2) < 0.018 and v < 0.36:
                    r, g, b = 0.12, 0.03, 0.02
                k = (j * n + i) * 4
                px[k:k + 4] = (r, g, b, 1.0)
        img.pixels = px
        img.pack()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55
    return mat


def ring_rivets(prefix, y, r, n=6, mat="Iron", rr=0.0065, front_only=False, phase=0.0):
    out = []
    for k in range(n):
        a = phase + TAU * k / n
        nrm = Vector((math.sin(a), 0.0, math.cos(a)))
        if front_only and nrm.z < -0.2:
            continue
        out.append(fin(stud(prefix, Vector((0.0, y, 0.0)) + nrm * r, nrm, mat, rr, rr * 0.65, 6)))
    return out


def ferrule(prefix, y_top, y_bot, r, mat="Iron", rivets=4):
    """Железная обойма на торце сегмента (как тёмные колпачки конечностей на листе автора) + заклёпки."""
    h = y_top - y_bot
    prof = [(0.0, y_top), (r * 0.82, y_top), (r, y_top - h * 0.25), (r, y_bot + h * 0.25), (r * 0.9, y_bot), (0.0, y_bot)]
    out = [fin(revolve(prefix, prof, mat, 22), 0.002, 1, uv="cyl")]
    if rivets:
        out += ring_rivets(prefix + "_Rivet", (y_top + y_bot) / 2, r, rivets, "Steel", min(0.008, r * 0.12), phase=math.pi / rivets)
    return out


def band(prefix, y, r, h, mat):
    return fin(revolve(prefix, [(r * 0.97, y + h / 2), (r, y + h * 0.3), (r, y - h * 0.3), (r * 0.97, y - h / 2)], mat, 22, closed=True),
               0.001, 1, uv="cyl")


def peg(name, y0, y1, r0, r1, mat, bulge=0.06, rings=9, segs=22):
    """Сегмент-«колышек» от y0 до y1 (y0 > y1): скруглённые торцы, лёгкая бочка посередине (игрушечный объём)."""
    L = y0 - y1
    prof = [(0.0, y0), (r0 * 0.78, y0 - 0.002), (r0 * 0.95, y0 - min(0.012, L * 0.1))]
    for i in range(rings + 1):
        t = i / rings
        y = y0 - min(0.02, L * 0.14) - (L - 2 * min(0.02, L * 0.14)) * t
        prof.append(((r0 + (r1 - r0) * t) * (1.0 + bulge * math.sin(math.pi * t)), y))
    prof += [(r1 * 0.95, y1 + min(0.012, L * 0.1)), (r1 * 0.78, y1 + 0.002), (0.0, y1)]
    return fin(revolve(name, prof, mat, segs), 0.0, uv="cyl")


def face_plate(name, center, w, h, bend=0.0, cols=8, rows=4, round_n=0.0):
    """FacePlate: прямоугольник w × h в плоскости XY (лицом к камере), UV 0..1; bend — изгиб по цилиндру (z −= bend·x²).
    round_n > 0 — углы скруглены по суперэллипсу |x/(w/2)|ⁿ + |y/(h/2)|ⁿ = 1 (как rounded_frame рамки): узлы сетки снаружи кривой
    сдвигаются на неё по лучу из центра, UV — плоская проекция (кадр 0..1 тот же, у фото срезаны только углы, а не сжаты)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    cx, cy, cz = center
    grid = []
    uvs = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            x = -w / 2 + w * i / cols
            py = cy - h / 2 + h * j / rows
            if round_n > 0.0:
                y = -h / 2 + h * j / rows
                e = abs(x / (w / 2)) ** round_n + abs(y / (h / 2)) ** round_n
                if e > 1.0:
                    k = e ** (-1.0 / round_n)
                    x, y = x * k, y * k
                uvs.append((x / w + 0.5, y / h + 0.5))
                py = cy + y
            row.append(bm.verts.new((cx + x, py, cz - bend * x * x)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for lp, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                lp[uvl].uv = uvs[jj * (cols + 1) + ii] if round_n > 0.0 else (ii / cols, jj / rows)
    bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(M("Face"))
    for p in me.polygons:
        p.use_smooth = True
    return o


def rounded_frame(name, center, hw, hh, minor, mat, z, bend=0.0):
    pts = [(x, y, z - bend * (x - center[0]) ** 2) for x, y in superellipse(center[0], center[1], hw, hh, 32, 5.0)]
    return fin(sweep(name, pts, minor, mat, sides=6, closed=True), angle=70)


def rbox(name, size, mat, center, r, segs=3):
    """Скруглённый брус (фаска с сегментами) — основа игрушечных голов, ядер, кистей."""
    return fin(box(name, size, mat, center), r, segs, angle=60.0, bevel_angle=30.0)


def porthole(prefix, center, r=0.062):
    """Окошко Ядра (лор: Ядро — сердце куклы): латунное кольцо, светящийся купол, две решётки, заклёпки."""
    cx, cy, cz = center
    objs = [fin(torus(prefix + "_Ring", center, r, r * 0.16, "Brass", 'XY', 28, 8), angle=80)]
    dome = sphere(prefix + "_Glow", r * 0.95, (cx, cy, cz - r * 0.55), "CoreGlow", 24, 12)
    objs.append(fin(dome, angle=80))
    for dx in (-0.33, 0.33):   # две вертикальные решётки — фонарь, а не крестик «закрыть»
        top = Vector((cx + dx * r, cy + r * 0.9, cz + r * 0.12))
        mid = Vector((cx + dx * r, cy, cz + r * 0.42))
        bot = Vector((cx + dx * r, cy - r * 0.9, cz + r * 0.12))
        objs.append(fin(sweep(prefix + "_Bar", [top, mid, bot], r * 0.065, "Iron", sides=6), angle=70))
    for k in range(6):
        a = TAU * k / 6 + 0.26
        p = Vector((cx + math.cos(a) * r * 1.3, cy + math.sin(a) * r * 1.3, cz - 0.004))
        objs.append(fin(stud(prefix + "_Rivet", p, (0, 0, 1), "Brass", r * 0.1, r * 0.07, 6)))
    return objs


def neck_stub(prefix):
    return [fin(revolve(prefix + "_Neck", [(0.0, 0.0), (0.034, 0.0), (0.036, 0.035), (0.062, 0.052), (0.062, 0.062), (0.0, 0.062)],
                        "Iron", 20), 0.003, 1, uv="cyl")]


HUMAN_ANCHORS = [("Neck", (0.0, 0.30, 0.0), 180.0), ("Shoulder_L", (0.22, 0.26, 0.0), 0.0), ("Shoulder_R", (-0.22, 0.26, 0.0), 0.0),
                 ("Hip_L", (0.10, -0.26, 0.0), 0.0), ("Hip_R", (-0.10, -0.26, 0.0), 0.0),
                 ("Side_L", (0.21, 0.0, 0.0), 60.0), ("Side_R", (-0.21, 0.0, 0.0), -60.0), ("Back", (0.0, 0.2, -0.14), 180.0)]


def limb_empties(L, r):
    return [socket(), anchor("End", (0.0, -L, 0.0)), anchor("Deco", (0.0, -0.035, 0.0)),
            shape_capsule("Limb", (0.0, -L / 2, 0.0), r, L + 2 * r * 0.4)]
