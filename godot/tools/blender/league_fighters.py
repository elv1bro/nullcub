"""Бойцы NULL League v2 — кадр стиля (docs/plan-demo/ART_NULL.md, «Детали лиги v2»): четыре бойца разных цивилизаций лиги из
деталей kit_league.py, у каждого своё нечеловеческое строение. Состав и позы — LEAGUE_FIGHTERS из tools/build_league.gd (оттуда же
чертежи для игры), детали — по каталогу кита (kit_catalog.json): кадр и игра не расходятся.

Вид бойца лиги (в игре — scripts/league/league_look.gd): шары суставов ужаты (LEAGUE_JOINT_SCALE) и светятся фиолетовым, как
и кольцо цвета игрока на ядре; на FacePlate вместо фото — визор с глазом (assets/textures/league/league_face.png).

Запуск:  blender -b --python godot/tools/blender/league_fighters.py -- out.png [samples]
"""
import ast
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
sys.argv = [sys.argv[0]]

import bpy  # noqa: E402

import body_kit as BK  # noqa: E402
import common as C  # noqa: E402
import craft_parts as K  # noqa: E402
import kit_league as KL  # noqa: E402
from craft_parts import T  # noqa: E402

FACE_PNG = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "textures", "league", "league_face.png"))
BUILD_LEAGUE = os.path.abspath(os.path.join(HERE, "..", "build_league.gd"))
CATALOG = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "models", "body", "kit", "kit_catalog.json"))
JR = {"Neck": 0.05, "Shoulder": 0.064, "Side": 0.062, "Elbow": 0.054, "Wrist": 0.044, "Hip": 0.076, "Knee": 0.066, "Ankle": 0.052}
NEXT = {"Shoulder": ["Elbow", "Wrist"], "Side": ["Elbow", "Wrist"], "Hip": ["Knee", "Ankle"]}
FIXED_KINDS = ("weapon_head", "deco", "armor")


def league_fighters():
    """LEAGUE_FIGHTERS из tools/build_league.gd — один источник поз для игры и кадра (литерал словаря GDScript = литерал Python)."""
    txt = open(BUILD_LEAGUE, encoding="utf-8").read()
    i = txt.index("const LEAGUE_FIGHTERS := ") + len("const LEAGUE_FIGHTERS := ")
    j = txt.index("\n}\n", i) + 2
    return ast.literal_eval(txt[i:j])


def part_index():
    """id PartDef (kit_limb_league_float_s) → (builder, kw, kind) по каталогу кита."""
    with open(CATALOG, encoding="utf-8") as f:
        cat = json.load(f)
    return {BK.snake(glb): (e["builder"], e.get("kw", {}), e.get("kind", "")) for glb, e in cat.items()}


def jr(group):
    return JR[group] * KL.LEAGUE_JOINT_SCALE


def fighter(f, idx):
    """Кукла для кадра по записи LEAGUE_FIGHTERS (как BodyBlueprint tools/build_league.gd): ядро, голова, цепи от якорей ядра;
    якорь без _L / _R — пара (правая — зеркало левой), с _R — только правая (строится у левого якоря и зеркалится)."""
    def node(pid, anchor, rot, group):
        builder, kw, kind = idx[pid]
        fixed = kind in FIXED_KINDS
        return {"part": builder, "kw": kw, "anchor": anchor, "rot": rot, "kids": [], "jr": 0.0 if fixed else jr(group),
                "joint": None if fixed else "Joint_Pin"}

    kids = [dict(node(f["head"], "Neck", 0.0, "Neck"))]
    for anchor, parts, rots, deco, _names in f["chains"]:
        base = anchor[:-2] if anchor.endswith(("_L", "_R")) else anchor
        groups = [base] + NEXT[base]
        chain = [node(p, "End" if i else base + "_L", rots[i], groups[min(i, 2)]) for i, p in enumerate(parts)]
        if deco:
            host = chain[-2] if len(chain) > 2 else chain[-1]
            host["kids"].append(dict(node(deco, "Deco", 0.0, base), joint=None))
        for a, b in zip(chain, chain[1:]):
            a["kids"].append(b)
        top = chain[0]
        if anchor.endswith("_R"):
            top["mirror_only"] = True
        else:
            top["sym"] = not anchor.endswith("_L")
        kids.append(top)
    root = {"part": idx[f["core"]][0], "kids": kids}
    bl = BK.Build(1)
    bl.place(root, T((0.0, 1.17, 0.0)))
    return bl


def league_face_material():
    m = bpy.data.materials.new("LeagueFace")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(FACE_PNG)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.4
    bsdf.inputs["Roughness"].default_value = 0.08
    return m


def league_look(objs, face, joint):
    """Вид бойца лиги: всё Shirt_* (шары суставов, кольцо цвета игрока) — светящийся фиолетовый, Face — визор с глазом."""
    for o in objs:
        if o.type != 'MESH':
            continue
        for i, m in enumerate(o.data.materials):
            if m is None:
                continue
            if m.name.startswith("Shirt"):
                o.data.materials[i] = joint
            elif m.name.startswith("Face"):
                o.data.materials[i] = face


def main():
    out = _args[0] if _args else "/tmp/league_fighters.png"
    samples = int(_args[1]) if len(_args) > 1 else 32
    scn, cam = BK.setup_scene((2600, 1000))
    scn.cycles.samples = samples
    face = league_face_material()
    joint = C.material("LeagueJoint", (0.14, 0.02, 0.38, 1.0), 0.3, 0.0, emission=(0.36, 0.04, 1.0, 1.0), emission_strength=1.2)
    idx = part_index()
    specs = []
    for fid, f in league_fighters().items():
        def build(f=f):
            objs = fighter(f, idx).finish((0.0, 0.0, 0.0))
            league_look(objs, face, joint)
            return objs
        specs.append((f["title"], "", build))
    items = BK.place_row(specs, gap=0.5)
    K._frame_and_render(scn, cam, items, out, [])
    print("league fighters →", out)


main()
