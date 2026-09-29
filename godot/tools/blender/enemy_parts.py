"""Детали врагов PvE (docs/plan-demo/LORE.md «Враги»): пока одна — толкающая метла Уборщика (Sweeper).

Запуск:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/enemy_parts.py [-- sweeper_broom]
Пишет godot/assets/models/enemies/<id>.glb и печатает треугольники и габариты (DIMS — для коллизий сцены
godot/scenes/enemies/<id>.tscn, собранной руками: две коробки Col_Handle / Col_Head).

Соглашения — как у tools/blender/weapons.py (оттуда же хелперы и материалы): метры; origin = точка ХВАТА; оружие вытянуто
вдоль +X; предмет в плоскости X–Z Blender, «лицо» в −Y → в Godot плоскость X–Y, лицо в +Z. Объекты Handle и Head.
Материалы с именами, которые понимает EnemyLook (scripts/enemies/enemy_look.gd): Wood*/Bristle — дерево и щетина
(× WOOD_TINT), Iron*/Rope — железо и верёвка. Враг перекрашивает их в «ржавчину Башни» сам.

Метла: тёмная рукоять 1.34 м с обмоткой у хвата и железным торцом, колодка поперёк рукояти 0.52 м (Т — толкающая метла),
13 пучков щетины веером наружу, две железные распорки «рукоять → колодка». Читается как метла с любого зума — длинная палка
с широкой щёткой, а не молот (прежний вариант handle_long + head_mallet в кадре выглядел длинной киянкой).
"""
import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import weapons as W  # noqa: E402  (хелперы геометрии и материалы оружия; main() там не запускается)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "enemies"))
BUDGET = 4000
IDS = ["sweeper_broom"]

# габариты для коллизий (м, Godot: X вдоль оружия, Y — поперёк в плоскости экрана)
DIMS = {
    "sweeper_broom": {
        "handle": {"x0": -0.12, "x1": 1.26, "r": 0.024},
        "head": {"cx": 1.33, "len_x": 0.25, "width_y": 0.52, "depth_z": 0.08},
        "mass_kg": 2.6,
    },
}


def mats():
    M = W.materials()
    M["Bristle"] = common.material("Bristle", W.srgb("b39458"), rough=0.9)
    M["Rope"] = common.material("Rope", W.srgb("8a6a3c"), rough=0.85)
    return M


def strut(name, p0, p1, r, mat):
    """Стержень между точками p0 и p1 (Blender, м)."""
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    o = common.add_cylinder(name, radius=r, depth=length, loc=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=8)
    # цилиндр вдоль Z → повернуть в плоскости X–Z на угол к оси Z
    o.rotation_euler = (0.0, math.atan2(dx, dz), 0.0)
    common.apply_transforms(o, rotation=True, scale=True)
    return W.finish(o, mat)


def build_sweeper_broom(M):
    d = DIMS["sweeper_broom"]
    h = d["handle"]
    handle = [W.finish(W.rod_x("Shaft", h["x0"] + 0.02, 1.20, h["r"]), M["WoodDark"])]
    handle.append(W.finish(W.rod_x("Butt", h["x0"], h["x0"] + 0.03, 0.03), M["IronDark"], bevel=0.004, segs=1))
    handle.append(W.finish(W.rod_x("Socket", 1.16, h["x1"], 0.034), M["IronDark"], bevel=0.004, segs=1))
    handle += W.wrap("Wrap", -0.06, 0.18, 5, 0.026, 0.006, M["Rope"])
    head = []
    hc = d["head"]["cx"] - 0.06                    # колодка — ближняя к рукояти часть головы
    wz = d["head"]["width_y"]
    block = W.cube("Block", (0.085, 0.075, wz), (hc, 0.0, 0.0))
    head.append(W.finish(block, M["Wood"], bevel=0.008, segs=2))
    for s in (-1, 1):
        head.append(strut("Brace_%d" % (s + 1), (1.10, 0.0, 0.0), (hc - 0.03, 0.0, s * wz * 0.33), 0.009, M["Iron"]))
        head.append(W.finish(W.sphere("Bolt_%d" % (s + 1), 0.012, (hc, -0.04, s * wz * 0.33), 8, 3), M["Iron"]))
    n = 13
    for i in range(n):
        z = (i - (n - 1) / 2) / ((n - 1) / 2) * (wz * 0.47)
        tuft = W.cube("Tuft_%d" % i, (0.17, 0.05, 0.03), (0.0, 0.0, 0.0))
        tuft.location = (hc + 0.0425 + 0.075, 0.0, z)
        tuft.rotation_euler = (0.0, math.radians(8.0 * z / (wz * 0.47)), 0.0)   # веер наружу
        common.apply_transforms(tuft, location=False, rotation=True, scale=True)
        head.append(W.finish(tuft, M["Bristle"], bevel=0.004, segs=1))
    return [common.join(handle, "Handle"), common.join(head, "Head")]


BUILDERS = {"sweeper_broom": build_sweeper_broom}


def main():
    ids = [a for a in common.args_after_dashdash() if a in BUILDERS] or IDS
    report = {}
    for wid in ids:
        common.reset_scene()
        objs = BUILDERS[wid](mats())
        st = common.stats()
        report[wid] = st["tris"]
        flag = "" if st["tris"] <= BUDGET else "  !!! OVER BUDGET %d" % BUDGET
        print("enemy part %-14s objects=%s tris=%d%s" % (wid, [o.name for o in objs], st["tris"], flag))
        common.export_glb(os.path.join(OUT, wid + ".glb"), objs)
    print("=== enemy parts tris === " + json.dumps(report))
    print("=== dims === " + json.dumps(DIMS))


if __name__ == "__main__":
    main()
