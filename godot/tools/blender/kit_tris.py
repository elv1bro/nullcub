"""Проверка деталей кита без экспорта: треугольники против бюджета, габарит, материалы, пустышки, META.
    Blender -b --python godot/tools/blender/kit_tris.py -- Head_ProVisor Limb_AoeBlade
Без имён — все детали модулей kit_pro и kit_aoe. Ничего не пишет на диск (в отличие от body_kit.py --export, который обновляет
glb и kit_catalog.json): удобно, пока деталь в работе. Код выхода 1, если деталь сверх бюджета."""
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as BK  # noqa: E402
import common as C  # noqa: E402
import craft_parts as K  # noqa: E402
from kit_common import kit_setup  # noqa: E402

args = [a for a in C.args_after_dashdash() if not a.startswith("--")]
bad = []
for glb, (builder, kw, size) in BK.catalog().items():
    mod = BK.BUILDERS[builder].__module__
    if (args and builder not in args and glb not in args) or (not args and mod not in ("kit_pro", "kit_aoe")):
        continue
    C.reset_scene()
    K._MATS.clear()
    kit_setup(export=True)
    K.RNG.seed(zlib.crc32(glb.encode()))
    res = BK.BUILDERS[builder](**kw)
    objs, empties = res[0], res[1]
    extra = list(res[2]) if len(res) > 2 else []
    main = C.join(objs, glb) if len(objs) > 1 else objs[0]
    tris = K.tri_count([main] + extra)
    lo, hi = K._bbox_g([main] + extra)
    mats = sorted({m.name for o in [main] + extra for m in o.data.materials if m is not None})
    budget = BK.TRI_BUDGET_CORE if builder.startswith("Core_") else BK.TRI_BUDGET
    ok = tris <= budget
    if not ok:
        bad.append(glb)
    print("TRIS %-30s %5d / %d %s | size %.2f x %.2f x %.2f | y %.2f..%.2f | mats %s | empties %s | meta %s" % (
        glb, tris, budget, "OK" if ok else "OVER", hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], lo[1], hi[1], ", ".join(mats),
        ", ".join(sorted(e.name.split(".")[0] for e in empties)), BK.meta_of(builder)))
print("RESULT", "OVER BUDGET: %s" % bad if bad else "all within budget")
if bad:
    sys.exit(1)
