#!/usr/bin/env python3
"""Арена «Void» — пустое чёрное поле как в Ragdoll Masters (2005): серый плоский пол во всю ширину, тонкие стены по краям,
чёрный задник с едва заметной сеткой. Никаких пропсов. Референс: кадры RM (docs/plan-demo/RM_MECHANICS.md, лист rm_sheet).

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/arena_void.py [-- Имя …]
    → godot/assets/models/arena/void/{Floor_Slab,Wall_Side,Grid_Backdrop}.glb   (≤ 3000 треугольников на модуль,
      скрипт падает при превышении)
    → godot/assets/textures/pbr/grid_void/albedo.png   (тайл сетки 8 × 8 м, 1024², numpy; он же вшит в Grid_Backdrop.glb)
Сцену собирает tools/build_arena_void.gd (→ scenes/arena/void.tscn).

Соглашения (ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (в Godot +Z, к камере).
Модули и origin (v6, 28.09: вид «плоский как RM» — камера fov 24°, видимая глубина пола и стен 1 м, чтобы верх пола и
внутренние грани стен не давали крупных трапеций; коллизии глубиной 3 м строит builder отдельно):
    Floor_Slab     пол 16 × 1 (глубина) × 1 м — толстая плита под всей шириной кадра (x = −8..8, под стенами): передняя
                   грань — светло-серая полоса внизу кадра, как пол RM; верхняя грань темнее (Void_Floor_Top), читается
                   тонкой тёмной кромкой. Шум 512², 1 тайл = 2 м, фаска 2 см. Origin — центр ВЕРХНЕЙ грани (z=0 — поверхность
                   пола; в Godot ставится на y=0).
    Wall_Side      боковая стена 1 × 1 (глубина) × 8 м на плите пола (внутренняя грань x=±7, внешняя ±8 = край кадра):
                   передняя грань тёмно-серая (Void_Wall — полоса края поля), остальные почти чёрные (Void_Wall_Side).
                   Origin — центр основания.
    Grid_Backdrop  квад 40 × 24 м лицом в −Y, материал без освещения (Background → glTF KHR_materials_unlit → в Godot
                   unshaded): тайл сетки 8 × 8 м, линии 2 px (1.6 см; на экране боя ≈ 1–2 px) с шагом 1 м, каждая 4-я — с
                   тусклым цветным оттенком (как CRT-сетка RM). После ACES линия на экране ≈ 0.04–0.08 люмы
                   на чёрном — «едва видна» (tests/void_snapshot.gd: grid_visible / grid_faint). UV: u = (x + 20) / 8, v = (z + 12) / 8 — линии попадают на целые
                   метры мира, если центр квада стоит на целых координатах. Origin — центр квада.
Материалы: Void_Floor / Void_Floor_Top, Void_Wall / Void_Wall_Side (Principled, запечённый в numpy шум, packed; грань
выбирается по нормали), Void_Grid (unlit).
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "arena", "void")
GRID_DIR = os.path.join(GODOT, "assets", "textures", "pbr", "grid_void")
GRID_PNG = os.path.join(GRID_DIR, "albedo.png")
TRI_BUDGET = 3000

# --- размеры (м) — синхронно с tools/build_arena_void.gd
FLOOR_W, FLOOR_D, FLOOR_T = 16.0, 1.0, 1.0
WALL_T, WALL_D, WALL_H = 1.0, 1.0, 8.0
BACK_W, BACK_H = 40.0, 24.0

# --- сетка задника: тайл GRID_TILE_M × GRID_TILE_M м, GRID_PPM пикселей на метр
GRID_TILE_M = 8
GRID_PPM = 128
GRID_LINE_PX = 2                        # толщина линии в текселях (1 тексель = 1/128 м тонул в мипмапах и фазе пикселя)
# v6: камера fov 24° видит задник крупнее (≈ 90–130 px на метр, линия 2 px без размытия мипмапами) — линии в 2.2 раза
# темнее v5, чтобы на экране контраст остался ≈ 0.04–0.08 люмы («едва видна», tests/void_snapshot.gd)
GRID_LINE = (0.10, 0.10, 0.11)          # sRGB 0..1: основная линия (≈ 26/255 в текстуре; на экране — едва серая)
GRID_ACCENT_V = {0: (0.05, 0.125, 0.135), 4: (0.12, 0.07, 0.145)}   # вертикальные линии x = 0 и 4 м тайла: бирюза / фиолет
GRID_ACCENT_H = {0: (0.145, 0.05, 0.06), 4: (0.06, 0.12, 0.07)}     # горизонтальные y = 0 и 4 м: бордо / зелень

# --- пол и стены: серый с лёгким шумом (sRGB-яркость базы, амплитуда шума в долях)
FLOOR_BASE, FLOOR_AMP = 0.27, 0.045     # передняя грань: на экране (ambient + солнце, ACES) ≈ 0.4 люмы — серый, не белый
FLOOR_TOP_BASE = 0.06                   # верх пола темнее передней грани: тонкая тёмная кромка, а не светлая трапеция
WALL_BASE, WALL_AMP = 0.1, 0.05         # передняя грань стены: тёмно-серая полоса края поля (фон — чёрный)
WALL_SIDE_BASE = 0.035                  # внутренние/верхние грани стен почти чёрные — перспектива их не выдаёт
NOISE_SIZE = 512
NOISE_TILE_M = 2.0


# ----------------------------------------------------------------------------------------------------------------- textures
def _periodic_blur(white, sigma_px):
    """Гауссово размытие через FFT — периодическое, поэтому тайл бесшовный."""
    n = white.shape[0]
    k = np.fft.fftfreq(n)
    g = np.exp(-2.0 * (math.pi ** 2) * (sigma_px ** 2) * (k[:, None] ** 2 + k[None, :] ** 2))
    r = np.real(np.fft.ifft2(np.fft.fft2(white) * g))
    return (r - r.mean()) / (r.std() + 1e-9)


def noise_image(name, base, amp, seed):
    """Бесшовный серый шум (три октавы) вокруг яркости base; byte-картинка sRGB, упакована (уйдёт в glb)."""
    rng = np.random.default_rng(seed)
    s = NOISE_SIZE
    n = (0.35 * _periodic_blur(rng.standard_normal((s, s)), 12.0)
         + 0.35 * _periodic_blur(rng.standard_normal((s, s)), 3.5)
         + 0.30 * _periodic_blur(rng.standard_normal((s, s)), 1.0))
    n /= n.std()
    v = np.clip(base * (1.0 + amp * n), 0.0, 1.0)
    px = np.ones((s, s, 4), np.float32)
    px[..., 0] = v
    px[..., 1] = v
    px[..., 2] = np.clip(v * 1.02, 0.0, 1.0)     # едва холодный серый
    img = bpy.data.images.new(name, s, s, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def grid_png():
    """Тайл сетки 8 × 8 м (1024²): чёрный фон, линии GRID_LINE_PX px с шагом 1 м (по центру — целый метр),
    цветные акценты на 0 и 4 м. → GRID_PNG."""
    s = GRID_TILE_M * GRID_PPM
    px = np.zeros((s, s, 4), np.float32)
    px[..., 3] = 1.0
    offs = [k - GRID_LINE_PX // 2 for k in range(GRID_LINE_PX)]      # 2 px: столбцы −1 и 0 (с переносом через край тайла)
    for i in range(GRID_TILE_M):
        for o in offs:
            c = (i * GRID_PPM + o) % s
            px[:, c, :3] = GRID_ACCENT_V.get(i, GRID_LINE)     # вертикальная линия (столбцы)
    for i in range(GRID_TILE_M):
        row = np.array(GRID_ACCENT_H.get(i, GRID_LINE), np.float32)
        for o in offs:
            r = (i * GRID_PPM + o) % s
            px[r, :, :3] = np.maximum(px[r, :, :3], row)      # горизонтальная линия (строки; пересечения — ярче из двух)
    os.makedirs(GRID_DIR, exist_ok=True)
    img = bpy.data.images.new("grid_void", s, s, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = GRID_PNG
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)
    print("grid", GRID_PNG, os.path.getsize(GRID_PNG))
    return GRID_PNG


# ---------------------------------------------------------------------------------------------------------------- materials
def lit_material(name, img, rough):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.extension = 'REPEAT'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = 0.0
    mat.use_backface_culling = True     # glTF doubleSided = false
    return mat


def unlit_material(name, png):
    """Background-шейдер на выходе материала → экспортёр glTF пишет KHR_materials_unlit (Godot: shading unshaded)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bg = nt.nodes.new('ShaderNodeBackground')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = C._load_packed(png)
    tex.extension = 'REPEAT'
    nt.links.new(tex.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 1.0
    nt.links.new(bg.outputs['Background'], out.inputs['Surface'])
    mat.use_backface_culling = True
    return mat


# ------------------------------------------------------------------------------------------------------------------ modules
def assign_by_normal(obj, mats, pick):
    """Несколько материалов на один меш: индекс грани = pick(нормаль). Фаска (модификатор) берёт материал соседней грани."""
    obj.data.materials.clear()
    for m in mats:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = pick(p.normal)


def floor_slab(name):
    o = C.add_cube(name, size=(FLOOR_W, FLOOR_D, FLOOR_T), loc=(0.0, 0.0, -FLOOR_T * 0.5))
    C.set_origin(o, (0.0, 0.0, 0.0))
    C.uv_box(o, scale=1.0 / NOISE_TILE_M, along='Y')
    front = lit_material("Void_Floor", noise_image("void_floor_noise", FLOOR_BASE, FLOOR_AMP, 51), 0.86)
    top = lit_material("Void_Floor_Top", noise_image("void_floor_top_noise", FLOOR_TOP_BASE, FLOOR_AMP, 53), 0.9)
    assign_by_normal(o, [front, top], lambda n: 1 if n.z > 0.9 else 0)
    C.bevel(o, width=0.02, segments=2)
    C.smooth(o, 40.0)
    return o


def wall_side(name):
    o = C.add_cube(name, size=(WALL_T, WALL_D, WALL_H), loc=(0.0, 0.0, WALL_H * 0.5))
    C.set_origin(o, (0.0, 0.0, 0.0))
    C.uv_box(o, scale=1.0 / NOISE_TILE_M, along='Z')
    front = lit_material("Void_Wall", noise_image("void_wall_noise", WALL_BASE, WALL_AMP, 52), 0.9)
    side = lit_material("Void_Wall_Side", noise_image("void_wall_side_noise", WALL_SIDE_BASE, WALL_AMP, 54), 0.95)
    assign_by_normal(o, [front, side], lambda n: 0 if n.y < -0.9 else 1)     # «лицо» в −Y (в Godot +Z, к камере)
    C.bevel(o, width=0.02, segments=2)
    C.smooth(o, 40.0)
    return o


def grid_backdrop(name):
    png = GRID_PNG if os.path.exists(GRID_PNG) else grid_png()
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, 0.0))
    o = bpy.context.active_object
    o.name = name
    o.data.transform(Matrix.Diagonal((BACK_W, BACK_H, 1.0, 1.0)))
    o.data.transform(Matrix.Rotation(math.pi / 2.0, 4, 'X'))      # +Z → −Y: лицом к камере
    me = o.data
    uv = C._ensure_uv(o)
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = ((co.x + BACK_W * 0.5) / GRID_TILE_M, (co.z + BACK_H * 0.5) / GRID_TILE_M)
    C.assign(o, unlit_material("Void_Grid", png))
    return o


MODULES = [
    ("Floor_Slab", floor_slab),
    ("Wall_Side", wall_side),
    ("Grid_Backdrop", grid_backdrop),
]


# ------------------------------------------------------------------------------------------------------------------- export
def tri_count(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ev.to_mesh_clear()
    return n


def export(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_materials='EXPORT', export_normals=True, export_texcoords=True,
                              export_animations=False, export_skins=False, export_cameras=False, export_lights=False,
                              export_image_format='AUTO')


def main():
    argv = C.args_after_dashdash()
    C.reset_scene()
    grid_png()   # детерминированно (без случайности), дёшево — всегда заново
    report = []
    for name, build in MODULES:
        if argv and name not in argv:
            continue
        obj = build(name)
        tris = tri_count(obj)
        path = os.path.join(OUT, name + ".glb")
        export(path, obj)
        report.append((name, tris, os.path.getsize(path)))
        bpy.data.objects.remove(obj, do_unlink=True)
    print("MODULE                 TRIS      BYTES")
    for name, tris, size in report:
        print("%-22s %6d %10d%s" % (name, tris, size, "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    bad = [r[0] for r in report if r[1] > TRI_BUDGET]
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


main()
