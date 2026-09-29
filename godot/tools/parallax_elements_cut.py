#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Лист элементов параллакса → отдельные PNG с alpha + manifest.json для ParallaxScatter3D (scenes/arena/parallax_scatter.gd).

Вход — лист генерации (ChatGPT и т.п., требования — docs/plan-demo/PARALLAX.md §«Бриф»): несколько объектов на
ровном фоне, объекты не касаются друг друга. Фон:
  • настоящая прозрачность (PNG RGBA, где ≥ 10 % пикселей alpha < 16 и ≥ 10 % alpha > 240) — берётся как есть;
  • иначе ровный цвет (лучше чистый зелёный #00FF00) — цвет фона = медиана рамки листа, alpha = smoothstep расстояния
    до него в RGB (KEY), кромка деконтаминируется (rgb = (rgb − (1 − a)·фон) / a), при зелёном фоне — подавление
    зелёного переливания (g ≤ max(r, b)). Фейковую alpha-виньетку (как у присланных webp) скрипт отличает по порогам
    и игнорирует.
Разбиение: маска alpha > 0.35 с закрытием (MERGE пкс — решётчатые фермы не распадаются на куски), связные области
площадью ≥ min_area; кроп по bbox + PAD, чужие части в bbox обнуляются. Якорь: «top» — объект касается верхнего края
листа (подвешен: цепи, крюки, крановые тросы), иначе «bottom» (стоит).

Выход в out_dir: <prefix>_NN.png (+ .import: VRAM-сжатие и мипмапы, см. GODOT_IMPORT) + manifest.json (дописывается: записи с тем же source заменяются):
  {"elements": [{"file", "w", "h", "anchor", "fill" (средняя alpha — доля закрытой площади bbox), "source",
                 "bbox": [x0, y0, x1, y1]}]}

Запуск: /usr/local/bin/python3 godot/tools/parallax_elements_cut.py <sheet> <out_dir> [--prefix mid_a] [--min-area 3000]
        [--preview /abs/preview.png] [--single] [--ppm 60]
  --single — вся картинка = один элемент (рендер одной 3D-конструкции: тонкий трос не должен отрезать ковш);
  --ppm — пикселей на метр источника (запечённые 3D-рендеры знают свой масштаб) → "m_per_px" в manifest: полоса
          ParallaxScatterBand тогда берёт настоящую высоту × scale_range вместо height_m.
"""
import argparse
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

KEY = (0.10, 0.28)      # расстояние до цвета фона (RGB 0..1): до — фон, после — объект
MERGE = 7               # закрытие маски, пкс
PAD = 6                 # поля кропа, пкс
TOUCH = 3               # «касается края листа», пкс


def smoothstep(x, e0, e1):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def real_alpha(a):
    return (a < 16).mean() >= 0.10 and (a > 240).mean() >= 0.10


def key_sheet(img):
    """RGBA-лист → (rgb float, alpha float, описание фона)."""
    arr = np.asarray(img.convert("RGBA"), np.float32) / 255.0
    rgb, a = arr[..., :3], arr[..., 3]
    if real_alpha(np.asarray(img.convert("RGBA"))[..., 3]):
        return rgb, a, "alpha"
    h, w = a.shape
    b = max(4, int(min(h, w) * 0.02))
    border = np.concatenate([rgb[:b].reshape(-1, 3), rgb[-b:].reshape(-1, 3),
                             rgb[:, :b].reshape(-1, 3), rgb[:, -b:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    d = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    a = smoothstep(d, *KEY)
    edge = (a > 0.02) & (a < 0.98)
    fixed = (rgb - (1.0 - a[..., None]) * bg) / np.maximum(a[..., None], 0.15)
    rgb = rgb.copy()
    rgb[edge] = np.clip(fixed[edge], 0.0, 1.0)
    green = bg[1] > bg[0] + 0.3 and bg[1] > bg[2] + 0.3
    if green:
        rgb[..., 1] = np.minimum(rgb[..., 1], np.maximum(rgb[..., 0], rgb[..., 2]))
    return rgb, a, "key rgb(%d,%d,%d)%s" % (*(bg * 255).astype(int), " +despill" if green else "")


def whole(rgb, a):
    """Один элемент: bbox всей alpha > 0.02 + PAD."""
    h, w = a.shape
    ys, xs = np.nonzero(a > 0.02)
    y0, y1 = max(0, ys.min() - PAD), min(h, ys.max() + 1 + PAD)
    x0, x1 = max(0, xs.min() - PAD), min(w, xs.max() + 1 + PAD)
    ea = a[y0:y1, x0:x1]
    return [{"rgb": rgb[y0:y1, x0:x1], "a": ea, "bbox": [int(x0), int(y0), int(x1), int(y1)],
             "anchor": "top" if y0 == 0 and (ea[:TOUCH + 1] > 0.35).any() else "bottom"}]


def split(rgb, a, min_area):
    h, w = a.shape
    # закрытие на листе с полями: иначе эрозия у края листа съедает касание верхнего края (якорь «top»)
    m = np.pad(a > 0.35, MERGE + 1, mode="edge")
    m = ndimage.binary_closing(m, structure=np.ones((3, 3)), iterations=MERGE)[MERGE + 1:-MERGE - 1, MERGE + 1:-MERGE - 1]
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        own = lab[sl] == i
        if own.sum() < min_area:
            continue
        y0, y1 = max(0, sl[0].start - PAD), min(h, sl[0].stop + PAD)
        x0, x1 = max(0, sl[1].start - PAD), min(w, sl[1].stop + PAD)
        region = ndimage.binary_dilation(lab[y0:y1, x0:x1] == i, iterations=PAD)
        ea = a[y0:y1, x0:x1] * region
        out.append({"rgb": rgb[y0:y1, x0:x1], "a": ea, "bbox": [x0, y0, x1, y1],
                    "anchor": "top" if y0 == 0 and (ea[:TOUCH + 1] > 0.35).any() else "bottom"})
    out.sort(key=lambda e: (e["bbox"][1] // 200, e["bbox"][0]))  # по строкам листа, слева направо
    return out


# Импорт Godot для элементов: VRAM-сжатие (BPTC на десктопе, 1 байт/пкс) + мипмапы. Без этого файла Godot берёт
# дефолт 2D — Lossless: текстура распаковывается на CPU при загрузке и лежит в видеопамяти несжатой (4 байта/пкс).
GODOT_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(png_path):
    with open(png_path + ".import", "w") as f:
        f.write(GODOT_IMPORT)


def to_png(rgb, a):
    arr = np.concatenate([rgb, a[..., None]], axis=2)
    return Image.fromarray(np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def preview(elems, path):
    tiles = [to_png(e["rgb"], e["a"]) for e in elems]
    th = 256
    tiles = [t.resize((max(1, int(t.width * th / t.height)), th), Image.LANCZOS) for t in tiles]
    W = sum(t.width for t in tiles) + 8 * (len(tiles) + 1)
    sheet = Image.new("RGBA", (max(W, 64), th + 16), (0, 0, 0, 255))
    yy, xx = np.mgrid[0:th + 16, 0:sheet.width]
    chk = np.where(((yy // 16 + xx // 16) % 2)[..., None] == 0, [70, 70, 80, 255], [110, 110, 120, 255])
    sheet = Image.fromarray(chk.astype(np.uint8), "RGBA")
    x = 8
    for t in tiles:
        sheet.alpha_composite(t, (x, 8))
        x += t.width + 8
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("out_dir")
    ap.add_argument("--prefix", default=None)
    ap.add_argument("--min-area", type=int, default=3000)
    ap.add_argument("--preview", default=None)
    ap.add_argument("--single", action="store_true")
    ap.add_argument("--ppm", type=float, default=0.0)
    args = ap.parse_args()
    src = os.path.basename(args.sheet)
    prefix = args.prefix or os.path.splitext(src)[0]
    img = Image.open(args.sheet)
    rgb, a, how = key_sheet(img)
    elems = whole(rgb, a) if args.single else split(rgb, a, args.min_area)
    os.makedirs(args.out_dir, exist_ok=True)
    man_path = os.path.join(args.out_dir, "manifest.json")
    manifest = {"elements": []}
    if os.path.exists(man_path):
        with open(man_path) as f:
            manifest = json.load(f)
    for e in manifest["elements"]:
        if e.get("source") == src:
            p = os.path.join(args.out_dir, e["file"])
            for q in (p, p + ".import"):
                if os.path.exists(q):
                    os.remove(q)
    manifest["elements"] = [e for e in manifest["elements"] if e.get("source") != src]
    for k, e in enumerate(elems):
        name = ("%s.png" % prefix) if args.single else ("%s_%02d.png" % (prefix, k))
        to_png(e["rgb"], e["a"]).save(os.path.join(args.out_dir, name), optimize=True)
        write_import(os.path.join(args.out_dir, name))
        rec = {"file": name, "w": int(e["a"].shape[1]), "h": int(e["a"].shape[0]), "anchor": e["anchor"],
               "fill": round(float(e["a"].mean()), 3), "source": src, "bbox": e["bbox"]}
        if args.ppm > 0:
            rec["m_per_px"] = round(1.0 / args.ppm, 6)
        manifest["elements"].append(rec)
    with open(man_path, "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    if args.preview:
        preview(elems, args.preview)
    print("%s: %s, %d элементов → %s (%s)" % (src, how, len(elems), args.out_dir,
                                             ", ".join("%dx%d%s" % (e["a"].shape[1], e["a"].shape[0],
                                                                     "↓" if e["anchor"] == "top" else "")
                                                       for e in elems)))


if __name__ == "__main__":
    main()
