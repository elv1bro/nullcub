"""Зрители-спрайты: модульные существа из деталей кита тела v2 (как бойцы — людей в мире нет, LORE_NULL.md §2), запечённые в
атлас. VARIANTS сборок × POSES поз (руки вниз / в стороны / вверх) — ячейки сетки COLS × ROWS, одинаковый масштаб: ячейка =
CELL_W × CELL_H м. В Godot толпа — один MultiMesh квадов с шейдером assets/shaders/crowd_sprite.gdshader (ячейка по экземпляру,
позы сменяются, когда толпа болеет): одна текстура и одна отрисовка на весь стадион вместо тысяч мешей.

Запуск (Blender 4.5 LTS):
  blender -b --python crowd_sprites.py -- --atlas      → assets/textures/crowd/crowd_atlas.png + crowd_atlas.json
  blender -b --python crowd_sprites.py -- --atlas --samples 8   (быстрее, шумнее)

Сборки — случайные, но детерминированные (SEED): голова, ядро, руки, ноги, кисти, стопы, краски деталей, цвет «рубашки» (цвет
игрока 1–4 — болельщики), иногда декор (корона, султан, антенна, флажок на спине, крылья).
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402
import craft_parts as K  # noqa: E402
import body_kit as BK  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(GODOT, "assets", "textures", "crowd")
OUT_PNG = os.path.join(OUT_DIR, "crowd_atlas.png")
OUT_JSON = os.path.join(OUT_DIR, "crowd_atlas.json")

VARIANTS = 16
POSES = 3
COLS = 8
ROWS = 6                      # 48 ячеек = 16 × 3; ячейки варианта идут подряд (вариант v → ячейки 3v, 3v+1, 3v+2)
CELL_W = 1.6                  # м
CELL_H = 2.25
PX_PER_M = 120                # 192 × 270 px на ячейку, атлас 1536 × 1620
SEED = 2026

HEADS = ["Head_Round", "Head_Crate", "Head_Bot", "Head_Horned", "Head_Cow", "Head_Devil", "Head_Skull", "Head_Can", "Head_Lantern"]
CORES = ["Core_Barrel", "Core_Crate", "Core_Ball", "Core_Boiler", "Core_Toy", "Core_Drum", "Core_Cage"]
ARMS = ["Limb_Basic", "Limb_Thick", "Limb_Spring", "Limb_Bone", "Limb_Tentacle", "Limb_Thin", "Limb_Curved", "Limb_Robotic", "Limb_Rope",
        "Limb_Fantasy"]
LEGS = ["Limb_Basic", "Limb_Thick", "Limb_Piston", "Limb_Bone", "Limb_Plate", "Limb_Thin", "Limb_Robotic", "Limb_Fantasy"]
HANDS = ["Hand_Mitten", "Hand_Claw", "Hand_Clamp", "Hand_Paddle", "Hand_Fist"]
FEET = ["Foot_Boot", "Foot_Peg", "Foot_Wheel", "Foot_Spring", "Foot_Flipper"]
PAINTS = ["Wood", "Maple", "WoodDark", "PaintRed", "PaintBlue", "PaintYellow", "PaintWhite", "PaintGreen", "RustRed", "Iron", "Rust",
          "Brass", "Bone", "Pink"]
TOPS = ["Deco_Crown", "Deco_Plume", "Deco_Antenna"]
BACKS = ["Deco_Banner", "Deco_Wings"]
# позы: (плечо, локоть) — угол от «вниз» в плоскости экрана; ноги чуть врозь
POSE_ARMS = [(20.0, 10.0), (100.0, 40.0), (160.0, 15.0)]


# Кэш деталей: сборка детали (фаски, булевы операции) — самое долгое; 48 кукол из ~40 деталей = сотни одинаковых сборок.
# Первая сборка остаётся скрытым прототипом, дальше — копии объекта и меша (свой меш: recolor меняет слоты материалов).
_PROTO = {}
_make_part_orig = BK.make_part


def _make_part_cached(name, kw, base=None):
    key = (name, tuple(sorted((k, repr(v)) for k, v in (kw or {}).items())), base)
    if key not in _PROTO:
        objs, marks = _make_part_orig(name, kw, base)
        for o in objs:
            o.hide_render = True
            o.hide_set(True)
        _PROTO[key] = (objs, marks)
    protos, marks = _PROTO[key]
    out = []
    for p in protos:
        o = p.copy()
        o.data = p.data.copy()
        o.hide_render = False
        bpy.context.scene.collection.objects.link(o)
        o.hide_set(False)
        out.append(o)
    return out, {k: m.copy() for k, m in marks.items()}


BK.make_part = _make_part_cached


def variant(i, rng):
    parts = {"head": rng.choice(HEADS), "core": rng.choice(CORES), "arm": rng.choice(ARMS), "leg": rng.choice(LEGS),
             "hand": rng.choice(HANDS), "foot": rng.choice(FEET), "player": rng.randint(1, 4)}
    bases = {}
    for k in ("head", "core", "arm", "leg"):
        if rng.random() < 0.7:
            bases[k] = rng.choice(PAINTS)
    extras = {}
    r = rng.random()
    if r < 0.28:
        extras["top"] = {"part": rng.choice(TOPS)}
    elif r < 0.45:
        extras["back"] = {"part": rng.choice(BACKS)}
    parts["bases"] = bases
    parts["extras"] = extras
    parts["leg_rest"] = (rng.uniform(4.0, 11.0), rng.uniform(0.0, 6.0))
    return parts


def build_doll(v, pose, offset):
    bl = BK.human(v["head"], v["core"], v["arm"], v["leg"], v["hand"], v["foot"], bases=v["bases"], extras=v["extras"],
                  player=v["player"], arm_rest=POSE_ARMS[pose], leg_rest=v["leg_rest"])
    return bl.finish(offset)


def render_atlas(samples=24):
    C.reset_scene()
    K._MATS.clear()
    BK.kit_setup()
    rng = random.Random(SEED)
    variants = [variant(i, rng) for i in range(VARIANTS)]
    scn = bpy.context.scene
    width, height = COLS * CELL_W, ROWS * CELL_H
    for vi, v in enumerate(variants):
        built = []
        k = 1.0   # один масштаб на все позы варианта: при смене позы зритель не «сжимается»
        for p in range(POSES):
            cell = vi * POSES + p
            c, r = cell % COLS, cell // COLS
            x = (c + 0.5) * CELL_W - width * 0.5
            y = (ROWS - 1 - r) * CELL_H + 0.06          # ноги у низа ячейки
            objs = build_doll(v, p, (x, y, 0.0))
            lo, hi = K._bbox_g(objs)
            k = min(k, (CELL_H - 0.12) / (hi.y - lo.y), (CELL_W - 0.06) / (2.0 * max(hi.x - x, x - lo.x)))
            built.append((objs, Vector((x, y, 0.0))))
        if k < 1.0:
            for objs, pivot in built:
                for o in objs:
                    mw = o.matrix_world.copy()
                    o.matrix_world = K.G2B @ (K.T(pivot) @ K.S((k, k, k)) @ K.T(-pivot)) @ K.B2G @ mw
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    scn.cycles.device = 'CPU'
    scn.render.film_transparent = True
    scn.render.resolution_x = int(width * PX_PER_M)
    scn.render.resolution_y = int(height * PX_PER_M)
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new("W")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.20, 0.21, 0.26, 1.0)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
    # свет как в зале: тёплый ключ спереди-сверху, холодный контровой сзади
    for nm, col, energy, rot in (("Key", (1.0, 0.8, 0.6), 3.4, (math.radians(35), 0, math.radians(-25))),
                                 ("Rim", (0.5, 0.62, 1.0), 2.5, (math.radians(-60), 0, math.radians(170))),
                                 ("Fill", (1.0, 0.9, 0.85), 0.8, (math.radians(70), 0, math.radians(40)))):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.color = col
        ld.energy = energy
        ld.angle = math.radians(10.0)
        lo_ = bpy.data.objects.new(nm, ld)
        scn.collection.objects.link(lo_)
        lo_.rotation_euler = rot
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = max(width, height)
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    cam.location = (0.0, -30.0, height * 0.5)   # Blender: камера на −Y смотрит в +Y (лицо кукол — Godot +Z = Blender −Y)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    cam_d.clip_end = 100.0
    scn.camera = cam
    os.makedirs(OUT_DIR, exist_ok=True)
    scn.render.filepath = OUT_PNG
    bpy.ops.render.render(write_still=True)
    meta = {"cols": COLS, "rows": ROWS, "variants": VARIANTS, "poses": POSES, "cell_m": [CELL_W, CELL_H], "px_per_m": PX_PER_M,
            "seed": SEED, "pose_arms": POSE_ARMS,
            "builds": [{k: v[k] for k in ("head", "core", "arm", "leg", "hand", "foot", "player", "bases")} |
                       {"extras": [e["part"] for e in v["extras"].values()]} for v in variants]}
    with open(OUT_JSON, "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("crowd atlas →", OUT_PNG, (scn.render.resolution_x, scn.render.resolution_y))


if __name__ == "__main__":
    args = C.args_after_dashdash()
    if "--atlas" in args:
        render_atlas(int(args[args.index("--samples") + 1]) if "--samples" in args else 24)
