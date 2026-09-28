"""Общие хелперы для headless-скриптов Blender (Blender 4.5 LTS, /Applications/Blender.app).

Запуск: /Applications/Blender.app/Contents/MacOS/Blender -b --python <script.py> -- <out.glb> [args]

Соглашения проекта (см. docs/plan-demo/ASSET_PIPELINE.md):
- метры; в Blender Z вверх, персонаж/предмет «смотрит» в -Y (это станет +Z в Godot после экспорта glTF с export_yup);
- X — вбок (влево/вправо на экране), как в Godot;
- каждая часть/модуль — отдельный объект с точным именем (Head, Torso, UpperArm_L, …; Stone_Block_A, Plank_2m, …);
- origin части куклы — в её проксимальном суставе; origin модуля арены — в его нижнем-левом углу или центре основания (документировать);
- материалы Principled BSDF: либо плоские (material()), либо PBR-набор из assets/textures/pbr (textured_material(),
  текстуры печёт tools/blender/textures.py); развёртки в метрах — uv_box()/uv_cylinder_along(), 1 тайл = 1 м;
  если нужен рисунок (сколы, дерево), запекать в изображение через bake_material() и подключать как Image Texture.
"""
import bpy
import bmesh
import math
import os
import sys


def args_after_dashdash():
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return []


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.unit_settings.system = 'METRIC'
    scn.unit_settings.scale_length = 1.0
    return scn


def material(name, base=(0.8, 0.8, 0.8, 1.0), rough=0.7, metal=0.0, emission=None, emission_strength=1.0):
    """Принципиальный материал; имя важно: Shirt/Face/Joint читает адаптер и сцены."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def smooth(obj, angle_deg=40.0):
    """Плавное затенение с автосглаживанием по углу (Blender 4.x: modifier Smooth by Angle)."""
    for p in obj.data.polygons:
        p.use_smooth = True
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))
    except Exception:
        pass
    return obj


def bevel(obj, width=0.01, segments=2, angle_deg=30.0):
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle_deg)
    return m


def subsurf(obj, levels=1):
    m = obj.modifiers.new("Subsurf", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    return m


def add_cube(name, size=(1, 1, 1), loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    apply_transforms(o, scale=True)
    return o


def add_cylinder(name, radius=0.1, depth=1.0, loc=(0, 0, 0), verts=24, radius_top=None, rot=(0, 0, 0)):
    """Цилиндр вдоль Z (или конус/усечённый, если radius_top задан)."""
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius_top, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def add_sphere(name, radius=0.1, loc=(0, 0, 0), segments=32, rings=16, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=segments, ring_count=rings)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    apply_transforms(o, scale=True)
    return o


def add_torus(name, major=0.5, minor=0.05, loc=(0, 0, 0), rot=(0, 0, 0), segs=32, ring=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot, major_segments=segs, minor_segments=ring)
    o = bpy.context.active_object
    o.name = name
    return o


def apply_transforms(obj, location=False, rotation=False, scale=True):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)


def join(objs, name):
    """Объединяет объекты в один меш (материалы сохраняются по слотам)."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.active_object
    j.name = name
    return j


def set_origin(obj, point):
    """Переносит origin объекта в мировую точку point, не двигая геометрию."""
    bpy.context.scene.cursor.location = point
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')


def parent(child, parent_obj, keep_transform=True):
    child.parent = parent_obj
    if keep_transform:
        child.matrix_parent_inverse = parent_obj.matrix_world.inverted()


def export_glb(path, objects=None, apply_modifiers=True):
    """Экспорт выбранных (или всех) объектов в GLB с Y вверх; Blender -Y → glTF +Z."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    if objects:
        for o in objects:
            o.select_set(True)
            for c in o.children_recursive:
                c.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=bool(objects),
        export_apply=apply_modifiers,
        export_yup=True,
        export_materials='EXPORT',
        export_normals=True,
        export_texcoords=True,
        export_animations=False,
        export_skins=False,
        export_cameras=False,
        export_lights=False,
    )
    print("exported", path, os.path.getsize(path))


def bake_material(obj, image_name, size=1024, bake_type='DIFFUSE', out_png=None):
    """Запекает цвет процедурного материала в изображение (Cycles). Медленно; использовать точечно."""
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = 16
    img = bpy.data.images.new(image_name, size, size)
    for mat in obj.data.materials:
        nodes = mat.node_tree.nodes
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = img
        nodes.active = tex
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scn.render.bake.use_pass_direct = False
    scn.render.bake.use_pass_indirect = False
    bpy.ops.object.bake(type=bake_type)
    if out_png:
        img.filepath_raw = out_png
        img.file_format = 'PNG'
        img.save()
    return img


def stats():
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return {"objects": len(bpy.context.scene.objects), "tris": tris}


# ----------------------------------------------------------------------------------------------------------------------
# PBR-текстуры (tools/blender/textures.py → assets/textures/pbr/<name>/) и развёртки в метрах
# ----------------------------------------------------------------------------------------------------------------------
PBR_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "textures", "pbr"))
TAU = 2.0 * math.pi


def _load_packed(path, non_color=False):
    """Загружает картинку (повторно — тот же datablock) и упаковывает её, чтобы glTF-экспорт вшил её в glb."""
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    if img.packed_file is None:
        img.pack()
    return img


def textured_material(name, folder, tint=None, metallic=None, roughness_scale=1.0, normal_strength=1.0):
    """Principled BSDF с набором PBR из assets/textures/pbr/<folder>/ (albedo.png sRGB, roughness.png, normal.png,
    опционально metallic.png — все Non-Color). folder — имя материала (wood, iron, stone, …) или абсолютный путь к папке.
    tint — RGBA, умножается на albedo через Mix(Multiply) → в glTF уходит как baseColorFactor.
    metallic — константа (иначе metallic.png, если есть, иначе 0). roughness_scale — Math(Multiply) → roughnessFactor.
    normal_strength — Strength ноды Normal Map → normalTexture.scale. Картинки упаковываются в .blend/glb.
    Одна текстура = 1 м (см. uv_box / uv_cylinder_along); повторное имя → тот же материал перенастраивается."""
    path = folder if os.path.isabs(folder) else os.path.join(PBR_DIR, folder)
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (-300, 0)
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    def tex_node(fname, non_color, y):
        p = os.path.join(path, fname)
        if not os.path.exists(p):
            return None
        n = nt.nodes.new('ShaderNodeTexImage')
        n.image = _load_packed(p, non_color)
        n.extension = 'REPEAT'
        n.interpolation = 'Linear'
        n.location = (-1100, y)
        return n

    alb = tex_node('albedo.png', False, 400)
    if alb is None:
        raise FileNotFoundError("нет albedo.png в " + path + " — запусти tools/blender/textures.py")
    if tint is not None:
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1.0
        mix.inputs[7].default_value = tuple(tint) if len(tint) == 4 else tuple(tint) + (1.0,)
        mix.location = (-700, 400)
        nt.links.new(alb.outputs['Color'], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    else:
        nt.links.new(alb.outputs['Color'], bsdf.inputs['Base Color'])
    rough = tex_node('roughness.png', True, 100)
    if rough is not None:
        if abs(roughness_scale - 1.0) > 1e-6:
            m = nt.nodes.new('ShaderNodeMath')
            m.operation = 'MULTIPLY'
            m.use_clamp = True
            m.inputs[1].default_value = roughness_scale
            m.location = (-700, 100)
            nt.links.new(rough.outputs['Color'], m.inputs[0])
            nt.links.new(m.outputs[0], bsdf.inputs['Roughness'])
        else:
            nt.links.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
    else:
        bsdf.inputs['Roughness'].default_value = 0.8 * roughness_scale
    if metallic is not None:
        bsdf.inputs['Metallic'].default_value = metallic
    else:
        met = tex_node('metallic.png', True, -200)
        if met is not None:
            nt.links.new(met.outputs['Color'], bsdf.inputs['Metallic'])
        else:
            bsdf.inputs['Metallic'].default_value = 0.0
    nrm = tex_node('normal.png', True, -500)
    if nrm is not None:
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nm.space = 'TANGENT'
        nm.inputs['Strength'].default_value = normal_strength
        nm.location = (-700, -500)
        nt.links.new(nrm.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def _ensure_uv(obj):
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    return me.uv_layers[0].data


def uv_box(obj, scale=1.0, along='Z'):
    """Кубическая проекция в локальных метрах: 1 тайл текстуры = 1/scale м (плотность одинакова на всех модулях).
    Ось `along` ('X'|'Y'|'Z') попадает в V текстуры — по ней идут волокна дерева; у граней, перпендикулярных ей,
    V = следующая ось. Применять после apply_transforms (масштаб должен быть вшит в меш)."""
    uv = _ensure_uv(obj)
    me = obj.data
    ai = 'XYZ'.index(along.upper())
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        rest = [k for k in range(3) if k != ax]
        if ai in rest:
            vax = ai
            uax = [k for k in rest if k != ai][0]
        else:
            uax, vax = rest
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co[uax] * scale, co[vax] * scale)


def uv_cylinder_along(obj, axis='Z', scale=1.0, around=None, centre=None):
    """Цилиндрическая развёртка вокруг локальной оси axis: V = координата вдоль оси (м × scale) — волокна/пряди идут
    вдоль сегмента; U = длина дуги (м × scale) либо, если задан `around`, доля окружности × around (верёвка: around=1 —
    ширина текстуры на весь обхват). Торцы (|n·axis| > 0.8) проецируются планарно. centre — центр оси в плоскости,
    перпендикулярной axis (по умолчанию середина bbox). Применять после apply_transforms."""
    uv = _ensure_uv(obj)
    me = obj.data
    ai = 'XYZ'.index(axis.upper())
    a1, a2 = [k for k in range(3) if k != ai]
    if centre is None:
        xs = [v.co[a1] for v in me.vertices]
        ys = [v.co[a2] for v in me.vertices]
        centre = ((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5)
    c1, c2 = centre
    radii = [math.hypot(v.co[a1] - c1, v.co[a2] - c2) for v in me.vertices]
    r_mean = max(1e-6, sum(radii) / max(1, len(radii)))
    circ = around if around is not None else TAU * r_mean * scale
    for poly in me.polygons:
        n = poly.normal
        if abs(n[ai]) > 0.8:
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                uv[li].uv = ((co[a1] - c1) * scale + 0.5 * circ, (co[a2] - c2) * scale)
            continue
        us = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            us.append(math.atan2(co[a2] - c2, co[a1] - c1) / TAU)
        if max(us) - min(us) > 0.5:
            us = [x + 1.0 if x < 0.0 else x for x in us]
        for li, uu in zip(poly.loop_indices, us):
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (uu * circ, co[ai] * scale)


def decal_plane(name, image_path, size=(0.5, 0.5), loc=(0, 0, 0), rot=(0, 0, 0)):
    """Квад с альфа-декалью (PNG с прозрачностью, например assets/textures/decals/crown.png), лицом в −Y (к камере в
    Godot); size = (ширина, высота) м, loc — мировая позиция центра, rot — Эйлер XYZ в радианах. Материал:
    Image → Base Color + Alpha, режим BLEND, без теней от прозрачных участков; картинка упаковывается в glb.
    Ставить на 5–10 мм перед поверхностью, чтобы не было z-fighting."""
    from mathutils import Matrix
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.transform(Matrix.Diagonal((size[0], size[1], 1.0, 1.0)))
    o.data.transform(Matrix.Rotation(math.pi / 2.0, 4, 'X'))   # +Z → −Y: лицом к камере
    mat = bpy.data.materials.new(name + "_Decal")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = _load_packed(image_path)
    tex.extension = 'CLIP'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = 0.7
    for attr, val in (('surface_render_method', 'BLENDED'), ('blend_method', 'BLEND'), ('shadow_method', 'CLIP')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    mat.use_backface_culling = True
    assign(o, mat)
    return o
