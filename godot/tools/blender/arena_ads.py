"""Рекламные щиты Лиги NULL для арен (23.10.2026): рама с экраном, щит на ферме-мачте, LED-лента для бортов трибун,
изогнутый баннер по стене купола, вертикальный флаг на мачте. Картинки — codex-реклама (tools/codex_art/arena_ads.py),
ставит их в бой scenes/arena/league_boards.gd (рантайм, без коллизий, вне поля боя).

Запуск (Blender 4.5 LTS):
  blender -b --python arena_ads.py -- --export                → assets/models/arena/ads/<Модуль>.glb + kit_report.json
  blender -b --python arena_ads.py -- --export Ad_Ribbon      → только названные модули

Координаты Godot (craft_parts.G2B): X вбок, Y вверх, лицо модулей смотрит в +Z (к камере). Origin — центр основания.
Материалы по ролям (в glb плоские, при импорте tools/import/role_import.gd ставит assets/materials/ads/<Роль>.tres):
  Ad_Steel, Ad_SteelDark (рамы, фермы), Ad_Yellow (предупредительная краска), Ad_Rubber (кабели),
  Ad_LightWarm, Ad_LightCool (огни), Ad_Screen (полотно рекламы; UV 0..1 на всё полотно, u вправо, v вниз в Godot —
  картинку кладёт league_boards.gd как surface override).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402
import craft_parts as K  # noqa: E402
from craft_parts import T, align_y, revolve, box, fin  # noqa: E402
import arena_null_hall as AH  # noqa: E402  (tube, truss, light_strip, screen_quad)

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "arena", "ads")
TRI_BUDGET = 3000
TRI_BUDGET_BIG = {"Ad_Billboard_Pole": 4000}   # щит + ферма-мачта + площадка
WARM = (1.0, 0.52, 0.16)

MODULES = ["Ad_Ribbon", "Ad_Billboard", "Ad_Billboard_Pole", "Ad_Banner_Curved", "Ad_Flag"]


def setup_materials(export=False):
    K.FLAT.update({
        "Ad_Steel": ((0.085, 0.09, 0.105, 1.0), 0.6, 0.4),
        "Ad_SteelDark": ((0.028, 0.029, 0.033, 1.0), 0.45, 0.6),
        "Ad_Yellow": ((0.82, 0.42, 0.02, 1.0), 0.6, 0.0),
        "Ad_Rubber": ((0.02, 0.02, 0.02, 1.0), 0.8, 0.0),
    })
    K.FORCE_FLAT = export
    k = 0.0 if export else 1.0
    K._MATS["Ad_LightWarm"] = C.material("Ad_LightWarm", (0.9, 0.5, 0.2, 1.0), 0.3, 0.0, emission=WARM + (1.0,),
                                         emission_strength=1.0 + 7.0 * k)
    K._MATS["Ad_LightCool"] = C.material("Ad_LightCool", (0.9, 0.92, 1.0, 1.0), 0.2, 0.0, emission=(1.0, 0.95, 0.88, 1.0),
                                         emission_strength=1.0 + 9.0 * k)
    K._MATS["Ad_Screen"] = C.material("Ad_Screen", (0.02, 0.03, 0.08, 1.0), 0.3, 0.0, emission=(0.1, 0.2, 0.5, 1.0),
                                      emission_strength=0.5)


def finish(objs, bevel=0.0):
    """Отделка всего, кроме полотен Ad_Screen (fin перезаписал бы их UV 0..1)."""
    out = []
    for o in objs:
        if o.data.materials and o.data.materials[0] is not None and o.data.materials[0].name.startswith("Ad_Screen"):
            out.append(o)
        else:
            out += AH.done([o], bevel)
    return out


def lamp(name, pos, aim):
    """Прожектор подсветки щита: стакан на штанге, стекло смотрит по aim."""
    xf = align_y(aim, pos)
    return [fin(revolve(name + "_Body", [(0.07, -0.12), (0.1, -0.05), (0.11, 0.07), (0.1, 0.09)], "Ad_SteelDark", 10, xf), 0.0),
            revolve(name + "_Lens", [(0.1, 0.088), (0.0, 0.095)], "Ad_LightCool", 10, xf)]


def framed_board(W, H, y0, depth=0.28, lamps=2):
    """Рама с экраном W×H, низ рамы на высоте y0: короб, полотно спереди, рёбра сзади, лампы на штангах сверху."""
    b = 0.16   # ширина рамы
    yc = y0 + b + H * 0.5
    objs = [box("Frame_T", (W + 2 * b, b, depth), "Ad_SteelDark", (0.0, yc + H * 0.5 + b * 0.5, 0.0)),
            box("Frame_B", (W + 2 * b, b, depth), "Ad_SteelDark", (0.0, yc - H * 0.5 - b * 0.5, 0.0)),
            box("Frame_L", (b, H, depth), "Ad_SteelDark", (-W * 0.5 - b * 0.5, yc, 0.0)),
            box("Frame_R", (b, H, depth), "Ad_SteelDark", (W * 0.5 + b * 0.5, yc, 0.0)),
            box("Back", (W, H, 0.06), "Ad_Steel", (0.0, yc, -depth * 0.5 + 0.03)),
            AH.screen_quad("Screen", W, H, (0.0, yc, depth * 0.5 - 0.06), "Ad_Screen"),
            AH.light_strip("Trim_B", (-W * 0.5, yc - H * 0.5 - b, depth * 0.5), (W * 0.5, yc - H * 0.5 - b, depth * 0.5), 0.045,
                           0.02, "Ad_LightWarm", normal=(0, 1, 0))]
    # задние рёбра (видны сбоку и сверху)
    for i in range(3):
        x = -W * 0.5 + W * (i + 0.5) / 3
        objs.append(box("Rib_%d" % i, (0.08, H + 2 * b, 0.22), "Ad_Steel", (x, yc, -depth * 0.5 - 0.11)))
    for i in range(lamps):
        x = -W * 0.5 + W * (i + 0.5) / lamps
        top = yc + H * 0.5 + b
        objs.append(AH.tube("Arm_%d" % i, (x, top, 0.0), (x, top + 0.18, 0.85), 0.025, "Ad_Steel", 6))
        objs += lamp("Lamp_%d" % i, Vector((x, top + 0.18, 0.92)), Vector((0.0, -0.75, -0.35)).normalized())
    return objs, yc


# ----------------------------------------------------------------------------------------------------------------------
# модули
# ----------------------------------------------------------------------------------------------------------------------
def build_Ad_Ribbon():
    """LED-лента борта трибуны 5.6 × 0.62 м (≈9:1) в тонком коробе. Origin — низ короба по центру, задняя стенка в z = 0."""
    W, H, D = 5.6, 0.62, 0.1
    objs = [box("Case", (W + 0.1, H + 0.1, D), "Ad_SteelDark", (0.0, (H + 0.1) * 0.5, D * 0.5)),
            AH.screen_quad("Screen", W, H, (0.0, (H + 0.1) * 0.5, D + 0.004), "Ad_Screen")]
    return finish(objs, 0.01), []


def build_Ad_Billboard():
    """Щит 16:9 (6.4 × 3.6 м) на двух опорах-ногах 1.2 м с подкосами и подсветкой. Origin — земля по центру."""
    W, H = 6.4, 3.6
    objs, yc = framed_board(W, H, 1.2)
    for sx in (-1, 1):
        x = sx * W * 0.32
        objs.append(box("Leg_%d" % sx, (0.22, 1.35, 0.22), "Ad_Steel", (x, 0.675, -0.2)))
        objs.append(AH.tube("Brace_%d" % sx, (x, 0.05, -1.4), (x, 1.3, -0.3), 0.05, "Ad_Steel", 6))
        objs.append(box("Foot_%d" % sx, (0.6, 0.08, 1.8), "Ad_Yellow", (x, 0.04, -0.7)))
    return finish(objs, 0.012), []


def build_Ad_Billboard_Pole():
    """Тот же щит 16:9 на ферме-мачте 7 м (как придорожная реклама над свалкой): трап, площадка. Origin — земля по центру."""
    W, H = 6.4, 3.6
    mast = 7.0
    objs, yc = framed_board(W, H, mast)
    objs += AH.truss("Mast", (0.0, 0.0, -0.45), (0.0, mast + 0.1, -0.45), 0.7, "Ad_SteelDark", 8, chord=0.05, diag=0.026, sides=4,
                     up=(0, 0, 1))
    objs.append(box("Deck", (W + 0.4, 0.08, 1.0), "Ad_Steel", (0.0, mast - 0.05, 0.55)))
    objs += AH.railing("Rail", -W * 0.5, W * 0.5, mast - 0.01, 1.0, mat="Ad_Yellow", h=0.6, post_step=1.6, r=0.022)
    objs.append(box("Plate", (1.6, 0.2, 1.6), "Ad_Steel", (0.0, 0.1, -0.45)))
    for sx in (-1, 1):
        objs.append(AH.tube("Arm_%d" % sx, (0.0, mast - 0.6, -0.45), (sx * W * 0.38, mast + 0.05, -0.3), 0.045, "Ad_SteelDark", 6))
    objs.append(AH.tube("Cable", (0.25, 0.2, -0.2), (0.25, mast, -0.2), 0.02, "Ad_Rubber", 6))
    return finish(objs, 0.012), []


def build_Ad_Banner_Curved():
    """Изогнутый баннер по стене купола: дуга R = 26 м на 26° (≈11.8 м), полотно 2.0 м + рельсы сверху и снизу.
    Origin — середина дуги у низа, вогнутость к +Z (центр окружности в z = +R): ставь на кольцо R лицом к центру."""
    R, SPAN, H = 26.0, math.radians(26.0), 2.0
    n = 16
    objs = []
    bm = bmesh.new()
    rows = []
    for j in range(2):
        row = []
        for i in range(n + 1):
            a = -SPAN * 0.5 + SPAN * i / n
            row.append(bm.verts.new((R * math.sin(a), 0.12 + j * H, R - R * math.cos(a))))
        rows.append(row)
    for i in range(n):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    scr = K._obj("Screen", bm, "Ad_Screen")
    # _obj пересчитывает нормали «наружу» — у открытой дуги это выпуклая сторона (от центра зала), и Godot отсекал
    # полотно как заднюю грань. Разворачиваем: лицо — вогнутая сторона, к центру (+Z).
    fb = bmesh.new()
    fb.from_mesh(scr.data)
    bmesh.ops.reverse_faces(fb, faces=fb.faces)
    fb.to_mesh(scr.data)
    fb.free()
    uvl = scr.data.uv_layers.new(name="UVMap")
    for loop in scr.data.loops:
        co = scr.data.vertices[loop.vertex_index].co   # Blender: X = Godot X, Z = Godot Y, Y = −Godot Z
        zg = -co.y
        a = math.atan2(co.x, R - zg)
        uvl.data[loop.index].uv = ((a + SPAN * 0.5) / SPAN, (co.z - 0.12) / H)
    objs.append(scr)
    # рельсы и стойки чуть позади полотна (радиус больше → дальше от центра)
    def arc_pt(a, y, r):
        return (r * math.sin(a), y, R - r * math.cos(a))
    for y, nm in ((0.06, "Rail_B"), (H + 0.18, "Rail_T")):
        pts = [Vector(arc_pt(-SPAN * 0.5 + SPAN * i / n, y, R + 0.06)) for i in range(n + 1)]
        objs.append(K.sweep(nm, pts, 0.07, "Ad_SteelDark", sides=6))
        pts = [Vector(arc_pt(-SPAN * 0.5 + SPAN * i / n, y + (0.09 if y < 1 else -0.09), R - 0.02)) for i in range(n + 1)]
        objs.append(K.sweep(nm + "_Glow", pts, 0.022, "Ad_LightWarm", sides=4))
    for i in range(0, n + 1, 4):
        a = -SPAN * 0.5 + SPAN * i / n
        objs.append(AH.tube("Post_%d" % i, arc_pt(a, 0.0, R + 0.12), arc_pt(a, H + 0.3, R + 0.12), 0.05, "Ad_Steel", 6))
    return finish(objs, 0.0), []


def build_Ad_Flag():
    """Вертикальный флаг-баннер 1.6 × 3.2 м (1:2) на мачте 6.2 м с перекладинами. Origin — земля у мачты, полотно справа (+X)."""
    W, H = 1.6, 3.2
    top = 6.0
    objs = [AH.tube("Pole", (0.0, 0.0, 0.0), (0.0, top + 0.2, 0.0), 0.06, "Ad_SteelDark", 10),
            AH.tube("Bar_T", (0.0, top, 0.0), (W + 0.25, top, 0.0), 0.035, "Ad_Steel", 6),
            AH.tube("Bar_B", (0.0, top - H, 0.0), (W + 0.25, top - H, 0.0), 0.035, "Ad_Steel", 6),
            box("Base", (0.6, 0.12, 0.6), "Ad_Yellow", (0.0, 0.06, 0.0)),
            box("Cap", (0.16, 0.12, 0.16), "Ad_LightWarm", (0.0, top + 0.26, 0.0)),
            AH.screen_quad("Screen", W, H - 0.1, (0.15 + W * 0.5, top - H * 0.5, 0.045), "Ad_Screen")]
    return finish(objs, 0.0), []


# ----------------------------------------------------------------------------------------------------------------------
def tris_of(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == 'MESH')


def export_all(names):
    os.makedirs(OUT, exist_ok=True)
    rp = os.path.join(OUT, "kit_report.json")
    report = {}
    if os.path.exists(rp):
        with open(rp) as f:
            report = json.load(f)
    bad = []
    for name in names:
        C.reset_scene()
        K._MATS.clear()
        setup_materials(export=True)
        objs, _ = globals()["build_" + name]()
        o = C.join(objs, name)
        tris = tris_of([o])
        budget = TRI_BUDGET_BIG.get(name, TRI_BUDGET)
        path = os.path.join(OUT, name + ".glb")
        C.export_glb(path, [o])
        mats = sorted({m.name for m in o.data.materials if m is not None})
        report[name] = {"tris": tris, "budget": budget, "bytes": os.path.getsize(path), "materials": mats}
        print("%-20s %5d / %5d tris  %s" % (name, tris, budget, ", ".join(mats)))
        if tris > budget:
            bad.append(name)
    with open(rp, "w") as f:
        json.dump(dict(sorted(report.items())), f, ensure_ascii=False, indent=1)
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


if __name__ == "__main__":
    args = C.args_after_dashdash()
    names = [a for a in args if a in MODULES] or MODULES
    if "--export" in args:
        export_all(names)
