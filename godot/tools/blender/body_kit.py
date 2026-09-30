#!/usr/bin/env python3
"""Кит тела v2 (29.09.2026, референс автора — лист «Ragdoll Master: build · fly · smash»): модульная кукла-игрушка из
отдельных деталей — головы со слотом под фото лица, ядра-хабы, видимые шарниры-коннекторы в цвете игрока, конечности
разных типов (одна система для рук и ног), кисти/стопы, броня и декор; материал — отдельная ось (Base_* подменяется).

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/body_kit.py -- --frame
        → кадр стиля: ряды рендера в $KIT_RENDER_TMP (по умолчанию <tmp>/body_kit_render) + meta.json
    python3 godot/tools/blender/body_kit.py --sheet [out.png]
        → лист-каталог из рядов (системный python3 + Pillow). Без пути: полный лист (2600 px, ~10 МБ) —
          $KIT_RENDER_TMP/body-kit-v2-full.png, копия для docs/ — docs/plan-demo/img/body-kit-v2.png (1480 px, PNG без
          потерь, ≤ 4 МБ; больше — ошибка, код 1, файл в docs/ не меняется). С путём — только полный лист по этому пути.
          (body-kit-v1.png — утверждённый кадр стиля 29.09, им не перезаписывать)
Переменные окружения: KIT_RENDER_SAMPLES (48), CRAFT_TEX_SIZE (512, текстуры внутри рендера).

Соглашения — как у tools/blender/craft_parts.py (его примитивы и материалы используются отсюда): геометрия в координатах
Godot (x вбок, +X = левая сторона куклы, y вверх, z к камере), origin детали = Socket, деталь растёт в −Y; Anchor_<имя> —
куда крепятся дети (−Y = куда вырастет ребёнок); голова и декор сверху растут вверх (Socket повёрнут на 180° вокруг Z).

Материалы по ролям (имя материала в glb — контракт для Godot-builder-а):
    Base_<Mat>   основной материал детали; <Mat> — материал по умолчанию, узел чертежа может заменить его (ось материалов);
    Shirt_Kit    цвет игрока (Doll._recolor перекрашивает всё, что начинается на «Shirt»): пояса ядер (≥ ~15 % силуэта ядра,
                 kit_cores._player_band), шары шарниров, флажок, ремни;
    Face         плашка под фото лица (объект FacePlate, UV 0..1);
    CoreGlow     окошко Ядра (эмиссия);
    остальное    фурнитура с постоянным материалом: Iron, Steel, Brass, Rubber, Bone, WoodDark, Rope…
"""
import json
import math
import os
import sys
import tempfile
import zlib

try:
    import bpy
    from mathutils import Matrix, Vector
except ImportError:  # системный python3: только --sheet
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# лист-каталог (--sheet без пути): копия для docs/ (SHEET_PNG) — уменьшенная до SHEET_DOC_W, PNG без потерь, не больше
# SHEET_DOC_MAX_BYTES (правило docs/ — BODY_KIT.md §1; при 1800 px шум рендера даёт 5.7 МБ, при 1480 — ~4.0); полный лист — SHEET_FULL
# (вне docs/). body-kit-v1.png — утверждённый кадр стиля, его не перезаписываем
SHEET_PNG = os.path.abspath(os.path.join(GODOT, "..", "docs", "plan-demo", "img", "body-kit-v2.png"))
SHEET_DOC_W = 1480
SHEET_DOC_MAX_BYTES = 4 * 1024 * 1024
RENDER_TMP = os.environ.get("KIT_RENDER_TMP") or os.path.join(tempfile.gettempdir(), "body_kit_render")
SHEET_FULL = os.path.join(RENDER_TMP, "body-kit-v2-full.png")
ROW_RES = (2600, 760)   # по умолчанию; у рядов каталога — свои (render_frame)
KIT_MODULES = ["kit_joints", "kit_heads", "kit_cores", "kit_limbs", "kit_ends", "kit_deco", "kit_weapons", "kit_league"]

if bpy is not None:
    import importlib

    import common as C  # noqa: E402
    import craft_parts as K  # noqa: E402
    from kit_common import *  # noqa: E402,F401,F403
    BUILDERS = {}
    for _m in KIT_MODULES:
        _mod = importlib.import_module(_m)
        for _n, _f in vars(_mod).items():
            if _n.startswith("build_") and callable(_f) and getattr(_f, "__module__", "") == _m:
                BUILDERS[_n[6:]] = _f
else:
    BUILDERS = {}
    PLAYER_LIN = []
    BASES = []


# ----------------------------------------------------------------------------------------------------------------------
# сборка кукол для кадра стиля (в Blender, по контракту child = anchor · Rz(угол) · socket⁻¹)
# ----------------------------------------------------------------------------------------------------------------------
def G(xf):
    return G2B @ xf @ B2G


def make_part(name, kw, base=None):
    """Строит деталь, склеивает меши в один объект (FacePlate — отдельно), читает маркеры в матрицы Godot."""
    fn = BUILDERS[name] if name in BUILDERS else getattr(K, "build_" + name)
    if base is not None and "base" in fn.__code__.co_varnames:
        kw = dict(kw, base=base)
    res = fn(**kw)
    objs, empties = res[0], res[1]
    extra = list(res[2]) if len(res) > 2 else []
    bpy.context.view_layer.update()
    main = C.join(objs, name) if len(objs) > 1 else objs[0]
    marks = {}
    for e in empties:
        marks[e.name.split(".")[0]] = B2G @ e.matrix_world @ G2B
        bpy.data.objects.remove(e, do_unlink=True)
    return [main] + extra, marks


def recolor(objs, old_prefix, new_name):
    for o in objs:
        if o.type != 'MESH':
            continue
        for i, m in enumerate(o.data.materials):
            if m is not None and m.name.startswith(old_prefix):
                o.data.materials[i] = M(new_name)


class Build:
    """Кукла для кадра: узел = (деталь, kwargs, base, якорь у родителя, угол, дети); sym — ещё и зеркальная копия (правая)."""

    def __init__(self, player=1):
        self.items = []     # (obj, Transform Godot)
        self.player = player

    def place(self, node, W_anchor, mirror=False, joint_r=0.0, joint="Joint_Pin"):
        part, kw, base, rot, kids = node["part"], node.get("kw", {}), node.get("base"), node.get("rot", 0.0), node.get("kids", [])
        objs, marks = make_part(part, kw, base)
        sock = marks.get("Socket", Matrix.Identity(4))
        W = W_anchor @ Rz(rot) @ sock.inverted()
        for o in objs:
            self.items.append((o, W, mirror))
        if joint_r > 0.0:
            jo, _ = make_part(node.get("joint", joint), {})
            for o in jo:
                self.items.append((o, W_anchor @ S((joint_r, joint_r, joint_r)), mirror))
        for kid in kids:
            an = kid["anchor"]
            Wa = W @ marks["Anchor_" + an]
            jr = kid.get("jr", JOINT_R.get(an.split("_")[0], 0.05))
            # mirror_only — поддерево только правой стороны (своя кисть / шарнир / декор): строится у левого якоря и зеркалится
            m = (not mirror) if kid.get("mirror_only") else mirror
            self.place(kid, Wa, m, jr if kid.get("joint", "Joint_Pin") else 0.0, kid.get("joint", "Joint_Pin") or "Joint_Pin")
            if kid.get("sym"):
                an_r = an[:-2] + "_R" if an.endswith("_L") else an
                if an_r != an and "Anchor_" + an_r in marks:
                    # правая сторона = зеркальная копия левого поддерева (ядро симметрично)
                    self.place(kid, W @ marks["Anchor_" + an], not mirror, jr, kid.get("joint", "Joint_Pin") or "Joint_Pin")

    def finish(self, offset):
        objs = []
        for o, W, mirror in self.items:
            o.matrix_world = G(T(offset) @ (MIR @ W if mirror else W))
            objs.append(o)
        bpy.context.view_layer.update()
        recolor(objs, "Shirt_Kit", "Shirt_P%d" % self.player)
        return objs


def human(head, core, arm, leg, hand, foot, bases=None, extras=None, player=1, arm_rest=(28.0, 12.0), leg_rest=(5.0, 0.0),
          right_arm=None, joints=None, right=None):
    """Чертёж «человек» на риге куклы v3: плечо 0.30 / предплечье 0.27, бедро 0.42 / голень 0.40.
    joints — коннекторы обеих сторон {"shoulder"|"elbow"|"wrist"|"hip"|"knee"|"ankle": "Joint_<Тип>"} (по умолчанию ось);
    right — правая рука не как левая: {"hand", "hand_base", "shoulder", "elbow", "wrist", "farm_deco"} поверх левой
    (wrist = None — без коннектора: навершие вместо кисти); строится зеркальной копией (Build, mirror_only)."""
    b = bases or {}
    ex = extras or {}
    jt = joints or {}
    arm_kw = [dict(L=0.30, r=0.058, ja=0.064, jb=0.054), dict(L=0.27, r=0.052, ja=0.054, jb=0.044)]
    leg_kw = [dict(L=0.42, r=0.074, ja=0.076, jb=0.066), dict(L=0.40, r=0.064, ja=0.066, jb=0.052)]

    def limb(part, kw, base, anchor, rot, kids, sym=True, deco=None, joint="Joint_Pin"):
        n = {"part": part, "kw": kw, "base": base, "anchor": anchor, "rot": rot, "kids": kids, "sym": sym, "joint": joint}
        if deco:
            n["kids"] = kids + [dict(deco, anchor="Deco", joint=None)]
        return n

    arm_part = arm if isinstance(arm, str) else arm[0]
    farm_part = arm if isinstance(arm, str) else arm[1]

    def arm_chain(o, sym):
        hand_n = {"part": o.get("hand", hand), "base": o.get("hand_base", b.get("hand")), "anchor": "End", "rot": 0.0,
                  "joint": o.get("wrist", jt.get("wrist", "Joint_Pin"))}
        lower = limb(farm_part, arm_kw[1], b.get("arm"), "End", arm_rest[1], [hand_n], sym=False, deco=o.get("farm_deco"),
                     joint=o.get("elbow", jt.get("elbow", "Joint_Pin")))
        return limb(arm_part, arm_kw[0], b.get("arm"), "Shoulder_L", arm_rest[0], [lower], sym=sym, deco=ex.get("shoulder"),
                    joint=o.get("shoulder", jt.get("shoulder", "Joint_Pin")))

    foot_n = {"part": foot, "base": b.get("foot"), "anchor": "End", "rot": 0.0, "joint": jt.get("ankle", "Joint_Pin")}
    upper_arm = arm_chain({}, sym=right_arm is None and right is None)
    lower_leg = limb(leg if isinstance(leg, str) else leg[1], leg_kw[1], b.get("leg"), "End", leg_rest[1], [foot_n], sym=False,
                     joint=jt.get("knee", "Joint_Pin"))
    upper_leg = limb(leg if isinstance(leg, str) else leg[0], leg_kw[0], b.get("leg"), "Hip_L", leg_rest[0], [lower_leg], sym=True,
                     deco=ex.get("thigh"), joint=jt.get("hip", "Joint_Pin"))
    kids = [{"part": head, "base": b.get("head"), "anchor": "Neck", "rot": 0.0,
             "kids": [dict(ex["top"], anchor="Top", joint=None)] if "top" in ex else []},
            upper_arm, upper_leg]
    if right is not None:
        kids.append(dict(arm_chain(right, sym=False), mirror_only=True))
    if right_arm is not None:
        kids.append(right_arm)
    if "back" in ex:
        kids.append(dict(ex["back"], anchor="Back", joint=None))
    root = {"part": core, "base": b.get("core"), "kids": kids}
    bl = Build(player)
    bl.place(root, T((0.0, 1.17, 0.0)))
    return bl


def right_side(chain):
    """Правая рука, отличная от левой: строится в левой системе и зеркалится (mirror=True через sym-механизм)."""
    return chain


# ----------------------------------------------------------------------------------------------------------------------
# кадр стиля: ряды рендера
# ----------------------------------------------------------------------------------------------------------------------
def _floor_offset(objs, x):
    lo, hi = K._bbox_g(objs)
    return lo, hi


def place_row(items_spec, gap=0.35, x0=0.0):
    """items_spec: [(label, sub, fn → [objs])]; раскладывает по X вплотную с зазором, на пол."""
    x = x0
    items = []
    for label, sub, fn in items_spec:
        objs = fn()
        lo, hi = K._bbox_g(objs)
        dx, dy = x - lo.x, -lo.y
        for o in objs:
            o.matrix_world = G(T((dx, dy, 0.0))) @ o.matrix_world
        bpy.context.view_layer.update()
        lo, hi = K._bbox_g(objs)
        items.append((label, sub, objs))
        x = hi.x + gap
    return items


def single(name, kw=None, base=None, xf=None, player=1):
    def fn():
        objs, _m = make_part(name, kw or {}, base)
        for o in objs:
            o.matrix_world = G(xf if xf is not None else Matrix.Identity(4))
        bpy.context.view_layer.update()
        recolor(objs, "Shirt_Kit", "Shirt_P%d" % player)
        return objs
    return fn


def build_fn(builder):
    def fn():
        bl = builder()
        return bl.finish((0.0, 0.0, 0.0))
    return fn


def mannequin_v3():
    """Текущая кукла (манекен v3, клён) для сравнения — только просмотр, файл не меняется."""
    path = os.path.join(GODOT, "assets", "models", "heroes", "mannequin_v3", "full", "light.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH' and not o.name.startswith("Face")]
    return objs


def setup_scene(res=None):
    K.ROW_RES = tuple(res or ROW_RES)
    scn, cam = K._setup_render_scene()
    kit_setup()
    scn.cycles.samples = int(os.environ.get("KIT_RENDER_SAMPLES", "48"))
    return scn, cam


def doll_builds():
    """Сборки кадра — как пресеты kit_* (BODY_KIT.md §3.5; ноги / руки — на риге v3, шарниры — типы пресета) + «вне пресетов»."""
    A = lambda: human("Head_Round", "Core_Barrel", "Limb_Basic", "Limb_Basic", "Hand_Mitten", "Foot_Boot", player=1)  # noqa: E731
    B = lambda: human("Head_Crate", "Core_Crate", "Limb_Thick", "Limb_Piston", "Hand_Mitten", "Foot_Boot", player=2,  # noqa: E731
                      bases={"hand": "RustRed"},
                      extras={"shoulder": {"part": "Deco_Pauldron", "base": "Iron"}}, right={"shoulder": "Joint_Motor"})
    Cb = lambda: human("Head_Bot", "Core_Ball", "Limb_Spring", "Limb_Piston", "Hand_Claw", "Foot_Peg", player=4,  # noqa: E731
                       bases={"core": "PaintBlue", "leg": "PaintWhite"}, arm_rest=(40.0, 25.0), leg_rest=(12.0, 8.0),
                       extras={"back": {"part": "Deco_Banner"}}, joints={"elbow": "Joint_Spring"})
    D = lambda: human("Head_Horned", "Core_Barrel", "Limb_Bone", "Limb_Plate", "Hand_Claw", "Foot_Boot", player=3,  # noqa: E731
                      bases={"core": "Iron", "foot": "Iron"},
                      extras={"thigh": {"part": "Deco_Spikes", "kw": {"r": 0.074}}}, joints={"knee": "Joint_Motor"})
    E = lambda: human("Head_Round", "Core_Ball", ("Limb_Thick", "Limb_Tentacle"), ("Limb_Basic", "Limb_Basic"), "Head_Mace_Ball",  # noqa: E731
                      "Foot_Boot", player=2, bases={"head": "PaintWhite", "core": "Rust", "arm": "PaintGreen", "leg": "WoodDark"},
                      extras={"top": {"part": "Deco_Crown"}}, arm_rest=(55.0, 30.0),
                      joints={"elbow": "Joint_Free"}, right={"elbow": "Joint_Spring"})
    F = lambda: human("Head_Devil", "Core_Toy", "Limb_Spiked", "Limb_Thin", "Hand_Claw", "Foot_Flipper", player=3,  # noqa: E731
                      bases={"core": "PaintRed", "foot": "PaintRed"}, extras={"back": {"part": "Deco_Wings"}},
                      joints={"knee": "Joint_Spring"}, right={"hand": "Hand_Fist"})
    Gs = lambda: human("Head_Skull", "Core_Cage", "Limb_Bone", "Limb_Bone", "Hand_Clamp", "Foot_Peg", player=4,  # noqa: E731
                       bases={"foot": "Bone"}, extras={"top": {"part": "Deco_Plume"}}, joints={"elbow": "Joint_Free"},
                       right={"elbow": "Joint_Pin", "farm_deco": {"part": "Deco_Gauntlet", "kw": {"r": 0.052}}})
    Hw = lambda: human("Head_Can", "Core_Drum", "Limb_Robotic", "Limb_Robotic", "Hand_Paddle", "Foot_Wheel", player=1,  # noqa: E731
                       extras={"top": {"part": "Deco_Antenna"}}, joints={"knee": "Joint_Spring"})
    Ln = lambda: human("Head_Lantern", "Core_Boiler", ("Limb_Curved", "Limb_Thin"), "Limb_Piston", "Hand_Clamp", "Foot_Boot",  # noqa: E731
                       player=2, bases={"foot": "Iron"}, extras={"back": {"part": "Deco_Chimney"}},
                       right={"hand": "Drill_Head", "wrist": None, "elbow": "Joint_Motor"})
    Cw = lambda: human("Head_Cow", "Core_Toy", "Limb_Rope", "Limb_Fantasy", "Hand_Mitten", "Foot_Spring", player=1,  # noqa: E731
                       extras={"top": {"part": "Deco_Crown"}}, joints={"ankle": "Joint_Free"})
    return [("Кит «Человек»", "бочка · круглая голова · базовые конечности · варежки · ботинки", A),
            ("Громила", "ящик · голова-ящик · толстые руки · поршни · железные наплечники; правое плечо — мотор", B),
            ("Робот", "хаб · экран · пружины · клешни · колышки · флажок; локти — пружина", Cb),
            ("Рогатый", "железная бочка · шлем · кости · бронеплиты · шипы; колени — мотор", D),
            ("Король-булава", "хаб · корона · щупальца с шаром булавы; левый локоть свободный", E),
            ("Чёртик", "игрушка · чёртик · шипастые · клешня + кулак · тонкие ноги · ласты · крылья", F),
            ("Скелет", "клетка · череп · кости · тиски · колышки · султан · наруч справа", Gs),
            ("Каталка", "бочка из-под масла · банка · робо-гидравлика · лопасти · колёса · антенна", Hw),
            ("Фонарщик", "котёл · фонарь · гнутая труба · тиски + бур · поршни · дымоход", Ln),
            ("Вне пресетов", "игрушка · корова · верёвки · сказочные ноги · пого-пружины", Cw)]


# материал по умолчанию (Base_<Mat>) → название MaterialDef (BODY_KIT.md §4), для подписей листа
MAT_TITLE = {"Wood": "дерево", "Maple": "клён", "WoodDark": "орех", "Planks": "доски", "PaintRed": "бордовая краска",
             "PaintBlue": "бирюзовая краска", "PaintYellow": "горчичная краска", "PaintWhite": "белая краска",
             "PaintGreen": "оливковая краска", "RustRed": "крашеный лист", "Iron": "железо", "Rust": "ржавчина", "Brass": "латунь",
             "Bone": "кость", "Pink": "резина"}


def part_spec(name, kw=None, xf=None, player=1, sub=None):
    """(название из META, материал по умолчанию, построитель) — ячейка ряда каталога."""
    import inspect
    meta = meta_of(name)
    fn = BUILDERS.get(name)
    base = ""
    if fn is not None:
        p = inspect.signature(fn).parameters
        if "base" in p and p["base"].default is not inspect.Parameter.empty:
            base = MAT_TITLE.get(p["base"].default, p["base"].default)
    return (meta.get("title", name), base if sub is None else sub, single(name, kw, xf=xf if xf is not None else preview_xf(name),
                                                                         player=player))


def render_frame():
    """Лист-каталог: все детали кита по рядам (у каждого ряда своё разрешение — ряды не пустые). Ряды пишутся в RENDER_TMP."""
    os.makedirs(RENDER_TMP, exist_ok=True)
    meta = {"rows": []}

    from bpy_extras.object_utils import world_to_camera_view

    def row(key, title, specs, gap, res):
        scn, cam = setup_scene(res)
        items = place_row(specs, gap=gap)
        out = os.path.join(RENDER_TMP, "row_%s.png" % key)
        labels = K._frame_and_render(scn, cam, items, out, [])
        # подпись — под самой нижней точкой детали в кадре: ласта, ботинок, колесо выступают к камере ниже Socket
        for lb, (_l, _s, objs) in zip(labels, items):
            ys = [(1.0 - world_to_camera_view(scn, cam, o.matrix_world @ Vector(c)).y) * res[1]
                  for o in objs if o.type == 'MESH' for c in o.bound_box]
            if ys:
                lb[3] = max(lb[3], round(max(ys)))
        meta["rows"].append({"title": title, "file": out, "labels": labels})
        print("row", key, "→", out)

    builds = [(t, s, build_fn(f)) for t, s, f in doll_builds()]
    up = Rz(180.0)
    # ряды 1–2: сборки как пресеты kit_* (+ текущая кукла для сравнения и сборка из деталей вне пресетов)
    row("builds", "Сборки из кита, как пресеты kit_* (цвет шарниров = цвет игрока; шарниры: ось / свободный / пружина / мотор)",
        [("Сейчас: манекен v3", "для сравнения", mannequin_v3)] + builds[:5], 0.45, (2600, 780))
    row("builds2", "Сборки из кита: новые пресеты и детали вне пресетов", builds[5:], 0.5, (2600, 780))
    # ряд 3: головы (слот под фото лица)
    heads = ("Head_Round", "Head_Crate", "Head_Bot", "Head_Horned", "Head_Cow", "Head_Devil", "Head_Skull", "Head_Can",
             "Head_Lantern")
    row("heads", "Головы (слот под фото лица; Top — место для декора)", [part_spec(n) for n in heads], 0.22, (2600, 560))
    # ряд 4: ядра (якоря тела, окошко Ядра)
    cores = ("Core_Barrel", "Core_Crate", "Core_Ball", "Core_Boiler", "Core_Toy", "Core_Drum", "Core_Cage")
    row("cores", "Ядра (8 якорей: шея, плечи, бёдра, бока, спина; окошко Ядра)", [part_spec(n) for n in cores], 0.24, (2600, 600))
    # ряд 5: конечности S (одна система для рук и ног; стоят на конце, Socket сверху)
    limbs = ("Limb_Basic", "Limb_Thick", "Limb_Spring", "Limb_Piston", "Limb_Bone", "Limb_Plate", "Limb_Tentacle", "Limb_Thin",
             "Limb_Curved", "Limb_Spiked", "Limb_Robotic", "Limb_Rope", "Limb_Fantasy")
    row("limbs", "Конечности, размер S (рука 0.30 м; L — нога 0.42 м): одна система для рук и ног",
        [part_spec(n, dict(SIZES["S"]), xf=up) for n in limbs], 0.17, (2600, 460))
    # ряд 6: кисти и стопы
    ends = ("Hand_Mitten", "Hand_Claw", "Hand_Clamp", "Hand_Fist", "Hand_Paddle", "Foot_Boot", "Foot_Peg", "Foot_Wheel",
            "Foot_Spring", "Foot_Flipper")
    row("ends", "Кисти и стопы (концевые детали)", [part_spec(n) for n in ends], 0.2, (2600, 420))
    # ряд 7: декор и броня (Top — голова, Back — ядро, Deco — конечность)
    deco = [("Deco_Horns", None), ("Deco_Crown", None), ("Deco_Plume", None), ("Deco_Antenna", None), ("Deco_Pauldron", None),
            ("Deco_Spikes", {"r": SIZES["S"]["r"]}), ("Deco_Gauntlet", {"r": SIZES["S"]["r"]}), ("Deco_Banner", None),
            ("Deco_Wings", None), ("Deco_Chimney", None)]
    row("deco", "Декор и броня: на голову (Top), на конечность (Deco), на спину (Back); fixed — масса и формы хозяину",
        [part_spec(n, kw) for n, kw in deco], 0.2, (2600, 480))
    # ряд 8: навершия (на конце конечности вместо кисти или в крафтовом оружии) и шарниры-коннекторы
    heads_w = ("Spear_Tip", "Drill_Head", "Saw_Disc", "Pick_Head", "Torch_Head", "Anchor_Head")
    js = S((0.09, 0.09, 0.09))
    specs = [part_spec(n, xf=up) for n in heads_w]
    specs += [part_spec(n, xf=js, player=p, sub=s) for n, p, s in (("Joint_Pin", 1, "мышца, энергия 0"),
                                                                   ("Joint_Free", 2, "без мышцы, 0"),
                                                                   ("Joint_Spring", 3, "мягкая мышца, 2"),
                                                                   ("Joint_Motor", 4, "сильная мышца, 8"))]
    row("weapons", "Навершия (вместо кисти или в оружии) · шарниры-коннекторы (цвет игрока; сварка — без коннектора)",
        specs, 0.22, (2600, 440))
    # ряд 9: ось материалов — одна и та же деталь
    row("mats", "Материал — отдельная ось: одна деталь, Base_* подменяется (плотность, трение, упругость, удар, магнит)",
        [(MAT_TITLE.get(b, b), b, single("Limb_Basic", base=b, xf=up)) for b in BASES], 0.1, (2600, 440))

    with open(os.path.join(RENDER_TMP, "meta.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("rendered rows →", RENDER_TMP)


# ----------------------------------------------------------------------------------------------------------------------
# экспорт деталей в glb для Godot (tools/build_body_kit.gd): assets/models/body/kit/<Имя>.glb
# ----------------------------------------------------------------------------------------------------------------------
OUT = os.path.join(GODOT, "assets", "models", "body", "kit")
TRI_BUDGET = 3000
TRI_BUDGET_CORE = 6000   # ядро — самая крупная деталь (торс v3 тоже тяжелее конечностей)
# размеры конечностей: S/L — кит (рука / нога), LA/LL — точные предплечье и голень рига куклы v3 (кит «человек»)
SIZES = {"S": dict(L=0.30, r=0.058, ja=0.064, jb=0.054), "LA": dict(L=0.27, r=0.052, ja=0.054, jb=0.044),
         "L": dict(L=0.42, r=0.074, ja=0.076, jb=0.066), "LL": dict(L=0.40, r=0.064, ja=0.066, jb=0.052)}


# Материал по умолчанию (Base_<Mat> в glb) → id MaterialDef (data/body/materials/<id>.tres, BODY_KIT.md §4)
BASE_TO_MAT = {"Wood": "wood", "Maple": "maple", "WoodDark": "wood_dark", "Planks": "planks", "PaintRed": "paint_red",
               "PaintBlue": "paint_blue", "PaintYellow": "paint_yellow", "PaintWhite": "paint_white", "PaintGreen": "paint_green",
               "RustRed": "rust_red", "Iron": "iron", "Rust": "rust", "Brass": "brass", "Bone": "bone", "Pink": "rubber"}
# материалы, которые тянет магнит Свалки: PartDef.material = "iron" (BODY_KIT.md §5.1); = колонка iron таблицы §4 (MaterialDef.iron,
# tools/build_body_kit.gd MATERIALS) — держать совпадающими, kit_probe сверяет material с MaterialDef(base_mat).iron
IRON_MATS = ("rust_red", "iron", "rust")
SIZE_PREFIX = {"S": "UpperArm", "LA": "LowerArm", "L": "UpperLeg", "LL": "LowerLeg"}
KIND_PREFIX = {"head": "Head", "core": "Torso", "hand": "Hand", "foot": "Foot", "deco": "Deco", "armor": "Armor", "joint": "Joint",
               "chain": "Chain", "handle": "Handle", "weapon_head": "WeaponHead", "mod": "Mod", "plate": "Plate"}
FIXED_KINDS = ("deco", "armor", "handle", "weapon_head", "mod", "plate")


def meta_of(builder):
    for m in KIT_MODULES:
        mod = sys.modules.get(m)
        if mod is not None and builder in getattr(mod, "META", {}):
            return dict(mod.META[builder])
    return {}


def snake(s):
    out = ""
    for i, ch in enumerate(s):
        if ch.isupper() and i > 0 and (s[i - 1].islower() or s[i - 1].isdigit()):
            out += "_"
        out += ch.lower()
    return out.replace("__", "_")


def catalog_entry(glb, builder, kw, size):
    """Строка kit_catalog.json для tools/build_body_kit.gd: всё, что нужно для PartDef и сцены."""
    import inspect
    meta = meta_of(builder)
    kind = meta.get("kind", "limb")
    fn = BUILDERS[builder]
    base = ""
    sig = inspect.signature(fn).parameters
    if "base" in sig and sig["base"].default is not inspect.Parameter.empty:
        base = BASE_TO_MAT.get(sig["base"].default, "")

    def per(v, default):
        if isinstance(v, dict):
            return v.get(size, default)
        return default if v is None else v

    e = {"glb": glb, "builder": builder, "size": size, "kind": kind, "title": meta.get("title", builder),
         "id": "kit_" + snake(glb[4:])}
    if kind == "connector":
        e["connector_type"] = builder.split("_", 1)[1].lower()
        return e
    if size:
        e["title"] = "%s %s" % (e["title"], {"S": "(рука)", "L": "(нога)", "LA": "(предплечье v3)", "LL": "(голень v3)"}[size])
    e.update({
        "mass": float(per(meta.get("mass"), 1.0)),
        "energy": int(per(meta.get("energy"), 3)),
        "attach": "fixed" if kind in FIXED_KINDS else "joint",
        "weapon_mult": float(per(meta.get("weapon_mult"), 1.0)),
        "name_prefix": meta.get("name_prefix") or (SIZE_PREFIX.get(size, "UpperArm") if kind == "limb" else KIND_PREFIX.get(kind, "Part")),
        "base_mat": base,
        "material": "iron" if base in IRON_MATS else "wood",
        "connector": kind in ("head", "limb", "hand", "foot", "joint", "chain"),
    })
    # body_mult — только у fixed-видов (декор / броня: бонус к удару телом-хозяином, BODY_KIT.md §6). У детали со своим телом удар —
    # Tuning.BODY_MULT по имени тела × материал: builder пишет в PartDef таблицу по name_prefix (§3.3), в каталоге ключа нет
    if kind in FIXED_KINDS:
        e["body_mult"] = float(per(meta.get("body_mult"), 1.0))
    # hit_mult — только у видов со своим телом и только если задан в META: множитель удара ЭТОЙ формой (шипы, рога, клешня; §3.3,
    # PartDef.hit_mult); нет ключа — 1.0 (builder)
    elif "hit_mult" in meta:
        e["hit_mult"] = float(per(meta.get("hit_mult"), 1.0))
    return e


def sized(builder):
    """Размеры детали: конечности — S/L (Limb_Basic ещё LA/LL для рига v3); прочие детали с параметром r (радиус конечности, на
    которую надеваются: шипы, наруч…) — S/L по SIZES[…]["r"]; остальные — без размера (кортеж пуст)."""
    import inspect
    if builder.startswith("Limb_"):
        return ("S", "LA", "L", "LL") if builder == "Limb_Basic" else ("S", "L")
    if builder in BUILDERS and "r" in inspect.signature(BUILDERS[builder]).parameters:
        return ("S", "L")
    return ()


def catalog():
    """Имя glb → (builder, kwargs, размер). Конечности — все параметры SIZES[размер]; детали с r — только r; остальное — по одной."""
    cat = {}
    for name in sorted(BUILDERS):
        sizes = sized(name)
        for sz in sizes:
            kw = dict(SIZES[sz]) if name.startswith("Limb_") else {"r": SIZES[sz]["r"]}
            cat["Kit_%s_%s" % (name, sz)] = (name, kw, sz)
        if not sizes:
            cat["Kit_" + name] = (name, {}, "")
    return cat


def _export_glb(path, objects):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_materials='EXPORT', export_normals=True, export_texcoords=True, export_animations=False,
                              export_skins=False, export_cameras=False, export_lights=False)


def export_parts(only):
    """Каждая деталь: меш (материалы по ролям, плоские), FacePlate отдельным объектом, пустышки Socket / Anchor_* / Shape_*.
    Печатает таблицу и JSON-сводку (=== body kit === {...}) — её читает tools/build_body_kit.gd (массы, габариты)."""
    report = {}
    bad = []
    cat_path = os.path.join(OUT, "kit_catalog.json")
    cat_out = {}
    if only and os.path.exists(cat_path):
        with open(cat_path) as f:
            cat_out = json.load(f)
    for glb, (builder, kw, size) in catalog().items():
        if only and glb not in only and builder not in only:
            continue
        C.reset_scene()
        K._MATS.clear()
        kit_setup(export=True)
        # случайные сдвиги UV (craft_parts.fin) и дрожь форм — от своего зерна у каждой детали: правка одной детали не
        # переставляет UV всех следующих по алфавиту, а экспорт одной детали = её экспорт в полном прогоне
        K.RNG.seed(zlib.crc32(glb.encode()))
        res = BUILDERS[builder](**kw)
        objs, empties = res[0], res[1]
        extra = list(res[2]) if len(res) > 2 else []
        main = C.join(objs, glb) if len(objs) > 1 else objs[0]
        main.name = glb
        tris = K.tri_count([main] + extra)
        path = os.path.join(OUT, glb + ".glb")
        _export_glb(path, [main] + extra + empties)
        lo, hi = K._bbox_g([main] + extra)
        mats = sorted({m.name for o in [main] + extra for m in o.data.materials if m is not None})
        entry = catalog_entry(glb, builder, kw, size)
        entry.update({"tris": tris, "empties": sorted(e.name.split(".")[0] for e in empties),
                      "materials": sorted({m.name for o in [main] + extra for m in o.data.materials if m is not None})})
        cat_out[glb] = entry
        report[glb] = {"builder": builder, "kw": kw, "tris": tris, "bytes": os.path.getsize(path),
                       "aabb": [list(lo), list(hi)], "materials": mats, "empties": sorted(e.name for e in empties)}
        if tris > (TRI_BUDGET_CORE if builder.startswith("Core_") else TRI_BUDGET):
            bad.append(glb)
        print("%-28s %5d tris %7d B  %s" % (glb, tris, os.path.getsize(path), ", ".join(mats)))
    os.makedirs(OUT, exist_ok=True)
    with open(cat_path, "w") as f:
        json.dump(dict(sorted(cat_out.items())), f, ensure_ascii=False, indent=1)
    print("catalog →", cat_path, len(cat_out), "entries")
    print("=== body kit === " + json.dumps(report, ensure_ascii=False))
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)



def preview_xf(name):
    """Как поставить деталь на пол в превью: конечности и кисти — вверх ногами (Socket сверху → стоят на конце)."""
    if name.startswith(("Limb_", "Hand_")) or name in ("Foot_Peg",):
        return Rz(180.0)
    if name.startswith("Foot_"):
        return T((0.0, 0.09, 0.0))
    if name.startswith("Joint_"):
        return S((0.07, 0.07, 0.07))
    return Matrix.Identity(4)


def render_preview(out_png, names, player=1, samples=8):
    """Превью для итераций: эталонная кукла кита «Человек» (масштаб) + ряд деталей; конечности и детали с r — в размере S.
    Имя с суффиксом @<Base> — деталь в другом материале (Limb_Basic@PaintBlue); с суффиксом ^L — размер L."""
    global ROW_RES
    ROW_RES = (2600, 900)
    scn, cam = setup_scene()
    scn.cycles.samples = samples
    specs = [("ref", "", build_fn(lambda: human("Head_Round", "Core_Barrel", "Limb_Basic", "Limb_Basic", "Hand_Mitten", "Foot_Boot",
                                                   player=player)))]
    for n in names:
        base = None
        size = "S"
        if "@" in n:
            n, base = n.split("@", 1)
        if "^" in n:
            n, size = n.split("^", 1)
        kw = dict(SIZES[size]) if n.startswith("Limb_") else ({"r": SIZES[size]["r"]} if sized(n) else {})
        specs.append((n, "", single(n, kw, base, xf=preview_xf(n), player=player)))
    items = place_row(specs, gap=0.18)
    K._frame_and_render(scn, cam, items, out_png, [])
    print("preview →", out_png)



def contact_sheet(out_png, doc_png=None):
    """Лист-каталог из рядов RENDER_TMP в полном размере → out_png; doc_png — ещё и уменьшенная копия для docs/ (_sheet_doc)."""
    from PIL import Image, ImageDraw, ImageFont
    with open(os.path.join(RENDER_TMP, "meta.json")) as f:
        meta = json.load(f)
    fp = '/System/Library/Fonts/Supplemental/Arial.ttf'
    font, small, big = ImageFont.truetype(fp, 22), ImageFont.truetype(fp, 17), ImageFont.truetype(fp, 30)
    head_h = 46
    rows = meta["rows"]
    ims = [Image.open(row["file"]).convert("RGB") for row in rows]   # у рядов своё разрешение (render_frame)
    W = max(im.width for im in ims)
    H = 64 + sum(im.height + head_h for im in ims)
    sheet = Image.new("RGB", (W, H), (18, 17, 20))
    d = ImageDraw.Draw(sheet)
    d.text((24, 16), "Кит тела v2 — каталог деталей (tools/blender/body_kit.py --frame; референс автора «Ragdoll Master: build · fly · smash»)",
           font=big, fill=(240, 236, 228))
    y = 64
    for row, im in zip(rows, ims):
        d.rectangle((0, y, W, y + head_h), fill=(34, 32, 38))
        d.text((24, y + 11), row["title"], font=font, fill=(255, 196, 120))
        y += head_h
        sheet.paste(im, (0, y))
        ends = []   # правый край подписи на каждом уровне: соседние длинные подписи уходят ниже, а не друг на друга
        for label, sub, px, py in row["labels"]:
            lines = [sub] if sub else []
            if sub and d.textlength(sub, font=small) > 300 and " · " in sub:
                parts = sub.split(" · ")   # длинная подпись сборки — в две строки по «·» ближе к середине
                k = min(range(1, len(parts)), key=lambda i: abs(len(" · ".join(parts[:i])) - len(sub) / 2))
                lines = [" · ".join(parts[:k]), " · ".join(parts[k:])]
            w = max([d.textlength(label, font=font)] + [d.textlength(s, font=small) for s in lines])
            lv = 0
            while lv < len(ends) and ends[lv] > px - w / 2 - 12:
                lv += 1
            if lv == len(ends):
                ends.append(0.0)
            ends[lv] = px + w / 2
            ty = y + min(py + 8 + (30 + 20 * len(lines)) * lv, im.height - 30 - 20 * len(lines))
            tw = d.textlength(label, font=font)
            d.text((px - tw / 2, ty), label, font=font, fill=(245, 242, 235))
            for i, s in enumerate(lines):
                sw = d.textlength(s, font=small)
                d.text((px - sw / 2, ty + 26 + 20 * i), s, font=small, fill=(170, 165, 158))
        y += im.height
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    sheet.save(out_png, optimize=True)
    print("sheet →", out_png, sheet.size, os.path.getsize(out_png), "B")
    if doc_png:
        _sheet_doc(sheet, doc_png)


def _sheet_doc(sheet, doc_png):
    """Копия листа для docs/: SHEET_DOC_W px по ширине (LANCZOS), RGB без палитры (палитра на 256 цветов — полосы на красном
    хабе), optimize=True. Больше SHEET_DOC_MAX_BYTES — ошибка (код 1), прежний файл в docs/ не трогается."""
    from PIL import Image
    doc = sheet.resize((SHEET_DOC_W, round(sheet.height * SHEET_DOC_W / sheet.width)), Image.LANCZOS)
    tmp = doc_png + ".tmp.png"
    os.makedirs(os.path.dirname(doc_png), exist_ok=True)
    doc.save(tmp, optimize=True)
    size = os.path.getsize(tmp)
    if size > SHEET_DOC_MAX_BYTES:
        os.remove(tmp)
        print("ERROR: sheet for docs %s is %d B > %d B (%dx%d) — docs/ не изменён" % (doc_png, size, SHEET_DOC_MAX_BYTES, *doc.size))
        sys.exit(1)
    os.replace(tmp, doc_png)
    print("sheet (docs) →", doc_png, doc.size, size, "B")


if __name__ == "__main__":
    if bpy is None:
        args = sys.argv[1:]
        if "--sheet" in args:
            i = args.index("--sheet")
            if len(args) > i + 1:
                contact_sheet(args[i + 1])                 # явный путь — только полный лист
            else:
                contact_sheet(SHEET_FULL, SHEET_PNG)       # полный — вне docs/, в docs/ — уменьшенная копия
    else:
        args = C.args_after_dashdash()
        if "--frame" in args:
            render_frame()
        elif "--preview" in args:
            i = args.index("--preview")
            render_preview(args[i + 1], [a for a in args[i + 2:] if not a.startswith("--")])
        elif "--export" in args:
            export_parts([a for a in args if a != "--export"])
