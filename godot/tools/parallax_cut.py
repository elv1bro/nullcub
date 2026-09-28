#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Резка листа R18 (docs/refs/R18-a-parallax-layers.jpg, 1619×971) на четыре слоя параллакса (ART_DIRECTION.md §4).

Выход — godot/assets/textures/parallax/:
  layer4_sky.png    RGB   небо и горы; сверху дорисовано небо, снизу — дымка долины (слой обязан закрывать весь кадр)
  layer3_far.png    RGBA  дальние руины и лес; небо вырезано в alpha; снизу — дымка (закрывает низ кадра за ареной)
  layer2_mid.png    RGBA  средний план построек; небо вырезано, нижние 12 % растворяются (за плитами арены)
  layer1_fore.png   RGBA  нижняя полоса растений/камней переднего плана; верх — градиент в прозрачность
Превью в перспективе, как из камеры игры (fov 45, две позиции): godot/tests/parallax_preview.png

Запуск: python3 godot/tools/parallax_cut.py [--preview-only] [--no-sharpen]
Зависимости: Pillow, numpy, scipy, opencv-python (системный /usr/local/bin/python3).

Что печатает: найденные прямоугольники панелей листа, пиксельные размеры слоёв и готовый блок размеров/позиций
квадов (метры) для scenes/arena/parallax_background.tscn. Геометрия слоёв (масштаб м/пкс, глубина z, якорная
строка → мировая высота) задана в LAYOUT ниже; превью и .tscn считаются из одних и тех же чисел.

Почему не просто «четыре панели как есть»:
- панели очень широкие (5.4:1 и 7:1), а кадр 16:9 и камера ездит по x на ±12 м → слои 4/3/2 продолжены по бокам
  содержимым противоположного края (wrap_extend; не зеркалом — зеркало даёт симметричные «бабочки» из ёлок и арок
  у оси; стык-кроссфейд ставится перебором туда, где обе стороны похожи и малодетальны, т.е. в дымке / на воде),
  слой 4 дорисован сверху (небо) и снизу (дымка), слой 3 — снизу (дымка), иначе в кадре дыры;
- по углам листа наложены размытые листья-виньетка и плашка с надписью → кропы обходят их, остатки на слое 4
  закрашиваются инпейнтом;
- панели 2 и 1 нарисованы одной картинкой с полупрозрачной тёмной полосой между ними: слой 2 берёт только свою панель
  и растворяется книзу (низ прячется за плитами арены), слой 1 — только нижнюю полосу растений/камней.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

try:
    import cv2
except ImportError:  # инпейнт остатков листьев на слое 4 — необязателен
    cv2 = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHEET = os.path.join(ROOT, "docs", "refs", "R18-a-parallax-layers.jpg")
OUT_DIR = os.path.join(ROOT, "godot", "assets", "textures", "parallax")
PREVIEW = os.path.join(ROOT, "godot", "tests", "parallax_preview.png")

OUT_WIDTH = 4096
CAM_FOV_DEG = 45.0
CAM_Z = 20.0

# Камера игры: центр по y 2.5..10, по x ±12, z 10..22 (DynamicCamera). Слои должны закрывать кадр во всём диапазоне.
VIEW_TOP_Y = 62.0     # самая верхняя точка кадра на плоскости слоя 4
VIEW_BOTTOM_Y4 = -47.0
VIEW_BOTTOM_Y3 = -28.0
VIEW_BOTTOM_Y1 = -7.0

# Кропы по x внутри каждой панели (обход виньетки из листьев и плашки с надписью; см. docstring).
# z — глубина квада; scale — метров на пиксель ЛИСТА; anchor_row (строка листа) → anchor_y (мировая высота).
# key: пороги кея неба (b−r от..до, value от..до) — у слоя 3 небо насыщенное (b−r≈0.33, дымка руин ≤0.18),
# у слоя 2 бледное (b−r≈0.15, дымка ≤0.15). extend: доля ширины, дорисовываемая с каждой стороны содержимым
# противоположного края (wrap_extend; панорама камеры ±12 м).
LAYOUT = {
    "layer4_sky": {"panel": 0, "x": (466, 1272), "z": -90.0, "scale": 0.21, "anchor_row": 215, "anchor_y": 1.5,
                    "extend": 0.15, "alpha": False},
    "layer3_far": {"panel": 1, "x": (345, 1420), "z": -45.0, "scale": 0.065, "anchor_row": 420, "anchor_y": 2.5,
                    "extend": 0.42, "alpha": True, "key": (0.20, 0.28, 0.60, 0.70), "top_soften": 0.30,
                    "top_fade": 0.14},
    "layer2_mid": {"panel": 2, "x": (290, 1445), "z": -18.0, "scale": 0.07, "anchor_row": 654, "anchor_y": -5.5,
                    "extend": 0.20, "alpha": True, "key": (0.10, 0.16, 0.55, 0.63), "top_soften": 0.15},
    "layer1_fore": {"panel": 3, "x": (300, 1440), "z": 2.5, "scale": 0.055, "anchor_row": 815, "anchor_y": 0.7,
                     "extend": 0.0, "alpha": True, "key": (0.20, 0.28, 0.60, 0.70)},
}
L1_ROWS = (795, 885)      # слой 1: полоса листа — верх плит земли (811), трава, размытые кусты (до ~885)
L1_RAMP = (805, 818)      # alpha 0 → 1 по строкам листа: выше кромки плит прозрачно
L2_BOTTOM_FADE = 0.12     # доля высоты слоя 2, растворяемая книзу (прячется за плитами арены)
TOP_FADE = 0.08           # верхние 8 % слоёв 3/2 — в прозрачность


# ---------------------------------------------------------------- утилиты

def smoothstep(x, e0, e1):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_img(arr):
    """float 0..1 (H,W,3|4) → PIL."""
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(a, "RGBA" if a.shape[2] == 4 else "RGB")


def find_panels(sheet, x0=216, x1=1518, dark=55.0, frac=0.8, min_h=150):
    """Прямоугольники панелей: строка — разделитель, если ≥ frac колонок x0..x1 темнее dark
    (средняя яркость строки не годится: внутри панели 1 тёмные холмы, а полосу между панелями 2 и 1
    пересекают постройки). Панель = пробег не-разделителей высотой ≥ min_h."""
    v = sheet[:, x0:x1, :].mean(axis=2)
    is_sep = (v < dark).mean(axis=1) > frac
    runs = []
    y = 0
    while y < len(is_sep):
        if is_sep[y]:
            y += 1
            continue
        y_start = y
        while y < len(is_sep) and not is_sep[y]:
            y += 1
        if y - y_start >= min_h:
            runs.append((y_start, y))
    return runs


def inpaint_dark_blobs(rgb, region_mask, v_thr=0.32, dilate=2):
    """Закрашивает почти чёрные размытые листья виньетки внутри region_mask (cv2 Telea)."""
    v = rgb.max(axis=2)
    m = (v < v_thr) & region_mask
    if dilate > 0:
        m = ndimage.binary_dilation(m, iterations=dilate)
    if cv2 is None or not m.any():
        return rgb, m
    src = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    out = cv2.inpaint(src[:, :, ::-1], m.astype(np.uint8) * 255, 6, cv2.INPAINT_TELEA)[:, :, ::-1]
    return out.astype(np.float32) / 255.0, m


def sky_alpha(rgb, key=(0.20, 0.28, 0.60, 0.70), top_soften=0.0, top_connected=True, feather_dilate=1,
              feather_sigma=1.6):
    """Мягкая маска неба → alpha (1 = объект). Правило: «сине-голубое и светлое» (b − r и value выше порогов key,
    b > g), плюс связность с верхним краем (синие флаги/двери внутри построек и озеро не вырезаются).
    Возвращает alpha, оценку цвета неба у кромки (для деконтаминации) и жёсткую маску."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    v = rgb.max(axis=2)
    br0, br1, v0, v1 = key
    if top_soften > 0.0:
        # у верхнего края панели (срез листа) пороги мягче: голубая дымка дальних руин тоже уходит в прозрачность,
        # чтобы срез не читался прямой линией; к глубине top_soften·H пороги приходят к key
        H = rgb.shape[0]
        k = smoothstep(np.arange(H, dtype=np.float32) / (top_soften * H), 0.0, 1.0)[:, None]
        br0 = 0.06 + (br0 - 0.06) * k
        br1 = br0 + (key[1] - key[0])
        v0 = 0.42 + (v0 - 0.42) * k
        v1 = v0 + (key[3] - key[2])
    score = smoothstep(b - r, br0, br1) * smoothstep(b - g, -0.005, 0.02) * smoothstep(v, v0, v1)
    hard = score > 0.5
    if top_connected:
        lab, n = ndimage.label(hard, structure=np.ones((3, 3)))
        top_ids = np.unique(lab[:3, :])
        top_ids = top_ids[top_ids > 0]
        keep = np.isin(lab, top_ids)
        # мелкие «острова» неба у самого верха (между зубцами) тоже считаем небом
        hard = keep
    sky = hard.astype(np.float32)
    if feather_dilate > 0:
        sky = ndimage.binary_dilation(hard, iterations=feather_dilate).astype(np.float32)
    sky = ndimage.gaussian_filter(sky, feather_sigma)
    # там, где жёсткая маска говорит «небо», прозрачность полная; мягкость — только внутрь объекта
    sky = np.maximum(sky, hard.astype(np.float32))
    alpha = 1.0 - sky
    # оценка цвета неба рядом с кромкой: нормированная свёртка по пикселям неба
    w = hard.astype(np.float32)
    est = np.zeros_like(rgb)
    den = ndimage.gaussian_filter(w, 12.0) + 1e-4
    for c in range(3):
        est[..., c] = ndimage.gaussian_filter(rgb[..., c] * w, 12.0) / den
    return alpha, est, hard


def decontaminate(rgb, alpha, sky_est):
    """Убирает подмес неба из полупрозрачных пикселей кромки: rgb = (rgb - (1-a)·sky)/a."""
    a = np.clip(alpha, 0.0, 1.0)[..., None]
    edge = (a > 0.02) & (a < 0.98)
    fixed = (rgb - (1.0 - a) * sky_est) / np.maximum(a, 0.15)
    out = rgb.copy()
    out[edge[..., 0]] = np.clip(fixed[edge[..., 0]], 0.0, 1.0)
    return out


def extend_rows(rgb, n, at_top, target_mult, tint, seam_rows=8, blur_x=14.0, reflect=0):
    """Дорисовка n строк сверху/снизу: цвет шва (среднее крайних строк, размытое по x) → к target (шов·mult·tint).
    Сверху крайние строки картинки подмешиваются к шву (нет линии). Снизу reflect строк — размытое затемнённое
    «отражение» (дымка/вода под лесом), плавно уходящее в градиент."""
    if n <= 0:
        return rgb
    rgb = rgb.copy()
    seam = rgb[:seam_rows].mean(axis=0) if at_top else rgb[-seam_rows:].mean(axis=0)
    seam = np.stack([ndimage.gaussian_filter1d(seam[:, c], blur_x, mode="reflect") for c in range(3)], axis=1)
    target = seam.mean(axis=0) * target_mult * np.asarray(tint, dtype=np.float32)
    t = np.linspace(0.0, 1.0, n, dtype=np.float32)
    t = t * t * (3.0 - 2.0 * t)
    if at_top:
        t = t[::-1]  # у шва (последняя строка блока) t=0 → цвет шва
    ext = seam[None, :, :] * (1.0 - t[:, None, None]) + target[None, None, :] * t[:, None, None]
    if at_top:
        k = min(seam_rows, rgb.shape[0])
        for i in range(k):  # растворить шов: верхние строки картинки тянутся к цвету шва
            w = (i + 1.0) / (k + 1.0)
            rgb[i] = rgb[i] * w + seam * (1.0 - w)
    elif reflect > 0:
        k = min(reflect, rgb.shape[0], n)
        refl = ndimage.gaussian_filter(rgb[-k:][::-1], (2.5, 1.0, 0.0))
        i = np.arange(k, dtype=np.float32)
        w = smoothstep(i / k, 0.0, 1.0)[:, None, None]
        dark = (0.85 - 0.35 * i / k)[:, None, None]
        ext[:k] = refl * dark * (1.0 - w) + ext[:k] * w
    rng = np.random.default_rng(7)
    ext += rng.normal(0.0, 1.0 / 255.0, ext.shape).astype(np.float32)  # дизеринг против полос
    ext = np.clip(ext, 0.0, 1.0)
    return np.concatenate([ext, rgb], axis=0) if at_top else np.concatenate([rgb, ext], axis=0)


def _band_cost(A, B):
    """Цена стыка двух полос (H,b,C): средняя разность цветов (там, где хоть одна сторона непрозрачна) + разность
    alpha (кромка неба) + детальность обеих полос (кроссфейд в дымке не виден, на башне — двоится)."""
    if A.shape[2] == 4:
        w = np.maximum(A[..., 3], B[..., 3])
        diff = (np.abs(A[..., :3] - B[..., :3]).mean(axis=2) * w).sum() / (w.sum() + 1e-6)
        diff += np.abs(A[..., 3] - B[..., 3]).mean()
        wd = w[:, 1:]
        det = ((np.abs(np.diff(A[..., :3], axis=1)).mean(axis=2) * wd).sum()
               + (np.abs(np.diff(B[..., :3], axis=1)).mean(axis=2) * wd).sum()) / (2.0 * wd.sum() + 1e-6)
    else:
        diff = np.abs(A - B).mean()
        det = 0.5 * (np.abs(np.diff(A, axis=1)).mean() + np.abs(np.diff(B, axis=1)).mean())
    return float(diff + 0.5 * det)


def wrap_extend(arr, frac, band=44, step=3, max_offset_frac=0.5):
    """Продолжает панораму по x на frac·W с каждой стороны содержимым ПРОТИВОПОЛОЖНОГО края (как тайл), а не
    зеркалом: зеркало у оси даёт симметричные «бабочки» из ёлок и арок. Стык — кроссфейд шириной band колонок
    исходника; смещение источника o перебирается так, чтобы обе стороны стыка были похожи и малодетальны
    (_band_cost) — шов уходит в дымку или на воду. Возвращает (arr, n, (o_left, o_right, cost_l, cost_r))."""
    if frac <= 0:
        return arr, 0, (0, 0, 0.0, 0.0)
    H, W = arr.shape[:2]
    n = int(round(W * frac))
    b = min(band, W // 8)
    t = smoothstep(np.linspace(0.0, 1.0, b, dtype=np.float32), 0.0, 1.0)[None, :, None]
    o_max = min(W - n - 1, int(W * max_offset_frac))
    # левое продолжение = arr[:, W-o-n : W-o]; стык между arr[:, 0:b] и arr[:, W-o : W-o+b]
    best_l = min(((_band_cost(arr[:, 0:b], arr[:, W - o:W - o + b]), o) for o in range(b, o_max + 1, step)))
    # правое продолжение = arr[:, o : o+n]; стык между arr[:, W-b:W] и arr[:, o-b : o]
    best_r = min(((_band_cost(arr[:, W - b:W], arr[:, o - b:o]), o) for o in range(b, o_max + 1, step)))
    cl, ol = best_l
    cr, orr = best_r
    mid = arr.copy()
    mid[:, 0:b] = arr[:, 0:b] * t + arr[:, W - ol:W - ol + b] * (1.0 - t)
    mid[:, W - b:W] = arr[:, W - b:W] * (1.0 - t) + arr[:, orr - b:orr] * t
    left = arr[:, W - ol - n:W - ol]
    right = arr[:, orr:orr + n]
    return np.concatenate([left, mid, right], axis=1), n, (ol, orr, round(cl, 3), round(cr, 3))


def upscale(arr, width, sharpen):
    img = to_img(arr)
    h = int(round(img.height * width / img.width))
    img = img.resize((width, h), Image.LANCZOS)
    if sharpen:
        if img.mode == "RGBA":
            rgb = img.convert("RGB").filter(ImageFilter.UnsharpMask(radius=2, percent=22, threshold=2))
            img = Image.merge("RGBA", (*rgb.split(), img.split()[3]))
        else:
            img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=22, threshold=2))
    return img


# ---------------------------------------------------------------- слои

def build_layers(sheet, panels, sharpen=True):
    """→ dict name → (PIL image, geometry dict). geometry: rows_total, anchor_row_local (в пикселях листа)."""
    out = {}
    for name, cfg in LAYOUT.items():
        py0, py1 = panels[cfg["panel"]]
        py0 += 2  # светлая антиалиасная кромка рамки листа (строки 20/268/462–463) и мягкие края разделителей
        py1 -= 1
        x0, x1 = cfg["x"]
        if name == "layer1_fore":
            py0, py1 = L1_ROWS
        crop = sheet[py0:py1, x0:x1, :].astype(np.float32) / 255.0
        H, W = crop.shape[:2]
        anchor_local = cfg["anchor_row"] - py0
        alpha = np.ones((H, W), dtype=np.float32)
        rgb = crop
        top_ext = bottom_ext = 0

        if name == "layer4_sky":
            yy, xx = np.mgrid[0:H, 0:W]
            region = ((xx < 70) | (xx > W - 100)) & (yy < int(H * 0.82))
            rgb, m = inpaint_dark_blobs(rgb, region)
            print(f"  {name}: инпейнт листьев {int(m.sum())} пкс")
            top_ext = int(math.ceil((VIEW_TOP_Y - cfg["anchor_y"]) / cfg["scale"])) - anchor_local
            bottom_ext = int(math.ceil((cfg["anchor_y"] - VIEW_BOTTOM_Y4) / cfg["scale"])) - (H - anchor_local)
            top_ext, bottom_ext = max(top_ext, 0), max(bottom_ext, 0)
            rgb = extend_rows(rgb, top_ext, True, 0.92, (0.80, 0.87, 1.0), seam_rows=6, blur_x=25.0)
            rgb = extend_rows(rgb, bottom_ext, False, 0.55, (0.92, 0.96, 1.05), reflect=40)
            alpha = None

        elif name in ("layer3_far", "layer2_mid"):
            alpha, sky_est, hard = sky_alpha(rgb, cfg["key"], top_soften=cfg.get("top_soften", 0.0))
            rgb = decontaminate(rgb, alpha, sky_est)
            print(f"  {name}: неба {100.0 * hard.mean():.1f} % панели")
            fade = smoothstep(np.arange(H, dtype=np.float32) / (cfg.get("top_fade", TOP_FADE) * H), 0.0, 1.0)
            alpha *= fade[:, None]
            if name == "layer2_mid":
                bf = smoothstep((H - 1 - np.arange(H, dtype=np.float32)) / (L2_BOTTOM_FADE * H), 0.0, 1.0)
                alpha *= bf[:, None]
            else:
                bottom_ext = int(math.ceil((cfg["anchor_y"] - VIEW_BOTTOM_Y3) / cfg["scale"])) - (H - anchor_local)
                bottom_ext = max(bottom_ext, 0)
                rgb = extend_rows(rgb, bottom_ext, False, 0.45, (0.90, 0.95, 1.05), reflect=60)
                alpha = np.concatenate([alpha, np.ones((bottom_ext, W), dtype=np.float32)], axis=0)

        elif name == "layer1_fore":
            a_sky, sky_est, hard = sky_alpha(rgb, cfg["key"])
            rgb = decontaminate(rgb, a_sky, sky_est)
            ramp = smoothstep(np.arange(H, dtype=np.float32), float(L1_RAMP[0] - py0), float(L1_RAMP[1] - py0))
            alpha = a_sky * ramp[:, None]
            bottom_ext = int(math.ceil((cfg["anchor_y"] - VIEW_BOTTOM_Y1) / cfg["scale"])) - (H - anchor_local)
            bottom_ext = max(bottom_ext, 0)
            rgb = extend_rows(rgb, bottom_ext, False, 0.35, (0.95, 0.97, 1.0), seam_rows=6, blur_x=20.0)
            alpha = np.concatenate([alpha, np.ones((bottom_ext, W), dtype=np.float32)], axis=0)

        if alpha is not None:
            arr = np.concatenate([rgb, alpha[..., None]], axis=2)
        else:
            arr = rgb
        arr, ext_px, seams = wrap_extend(arr, cfg["extend"])
        img = upscale(arr, OUT_WIDTH, sharpen)
        rows_total = arr.shape[0]
        cols_total = arr.shape[1]
        geom = {
            "rows_total": rows_total, "cols_total": cols_total, "anchor_local": anchor_local + top_ext,
            "width_m": cols_total * cfg["scale"], "height_m": rows_total * cfg["scale"],
            "y_top": cfg["anchor_y"] + (anchor_local + top_ext) * cfg["scale"],
            "z": cfg["z"], "crop": (x0, py0, x1, py1), "top_ext": top_ext, "bottom_ext": bottom_ext,
            "ext_px": ext_px, "seams": seams,
        }
        geom["y_centre"] = geom["y_top"] - geom["height_m"] / 2.0
        out[name] = (img, geom)
        print(f"  {name}: кроп x{x0}..{x1} y{py0}..{py1} → {cols_total}×{rows_total} пкс листа "
              f"(верх +{top_ext}, низ +{bottom_ext}, продолжение ±{ext_px}, швы o_l/o_r/цена {seams}) → "
              f"{img.width}×{img.height}")
    return out


# ---------------------------------------------------------------- превью

def project(cam, z, y_centre, w, h, size_px=(1280, 720)):
    """Прямоугольник квада (центр (0,y_centre), размер w×h на глубине z) в пикселях кадра камеры cam=(x,y,z)."""
    cx, cy, cz = cam
    d = cz - z
    hh = math.tan(math.radians(CAM_FOV_DEG / 2.0)) * d
    s = size_px[1] / 2.0 / hh
    x0 = size_px[0] / 2.0 + (-w / 2.0 - cx) * s
    x1 = size_px[0] / 2.0 + (w / 2.0 - cx) * s
    y0 = size_px[1] / 2.0 - (y_centre + h / 2.0 - cy) * s
    y1 = size_px[1] / 2.0 - (y_centre - h / 2.0 - cy) * s
    return x0, y0, x1, y1, s


def paste_quad(canvas, img, rect):
    x0, y0, x1, y1 = rect
    W, H = canvas.size
    pw, ph = int(round(x1 - x0)), int(round(y1 - y0))
    if pw <= 0 or ph <= 0:
        return
    sub = img.resize((pw, ph), Image.BILINEAR)
    # обрезка по холсту, чтобы не плодить гигантские промежуточные картинки
    ox, oy = int(round(x0)), int(round(y0))
    cx0, cy0 = max(0, -ox), max(0, -oy)
    cx1, cy1 = min(pw, W - ox), min(ph, H - oy)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    sub = sub.crop((cx0, cy0, cx1, cy1))
    if sub.mode == "RGBA":
        canvas.alpha_composite(sub, (ox + cx0, oy + cy0))
    else:
        canvas.paste(sub, (ox + cx0, oy + cy0))


def render_preview(layers, cam, size=(1280, 720)):
    canvas = Image.new("RGBA", size, (40, 60, 90, 255))
    order = ["layer4_sky", "layer3_far", "layer2_mid"]
    for name in order:
        img, g = layers[name]
        x0, y0, x1, y1, _ = project(cam, g["z"], g["y_centre"], g["width_m"], g["height_m"], size)
        paste_quad(canvas, img, (x0, y0, x1, y1))
    # плоскость боя z=0: плита земли (как арена: верх y=0, обрыв до -3, x ±14) и силуэт куклы 1.64 м
    from PIL import ImageDraw
    d = ImageDraw.Draw(canvas)
    x0, y0, x1, y1, s = project(cam, 0.0, -1.5, 28.0, 3.0, size)
    d.rectangle([x0, y0, x1, y1], fill=(96, 92, 86, 255))
    for dx in (0.0, 3.0):
        hx0, hy0, hx1, hy1, _ = project(cam, 0.0, 0.82, 0.5, 1.64, size)
        d.rectangle([hx0 + dx * s, hy0, hx1 + dx * s, hy1], fill=(255, 140, 40, 255), outline=(40, 20, 10, 255))
        d.ellipse([hx0 + dx * s - 2, hy0 - 8, hx1 + dx * s + 2, hy0 + 24], fill=(255, 170, 70, 255))
    img, g = layers["layer1_fore"]
    x0, y0, x1, y1, _ = project(cam, g["z"], g["y_centre"], g["width_m"], g["height_m"], size)
    paste_quad(canvas, img, (x0, y0, x1, y1))
    return canvas.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview-only", action="store_true", help="не писать PNG слоёв, только превью")
    ap.add_argument("--no-sharpen", action="store_true")
    args = ap.parse_args()

    sheet = np.asarray(Image.open(SHEET).convert("RGB"))
    print(f"лист {SHEET}: {sheet.shape[1]}×{sheet.shape[0]}")
    panels = find_panels(sheet)
    names = ["Layer 4 sky & mountains", "Layer 3 distant ruins & forest", "Layer 2 midground", "Layer 1 foreground"]
    if len(panels) != 4:
        sys.exit(f"ожидал 4 панели, нашёл {panels}")
    for n, (y0, y1) in zip(names, panels):
        print(f"  панель {n}: строки {y0}..{y1 - 1} (высота {y1 - y0})")
    print("слои:")
    layers = build_layers(sheet, panels, sharpen=not args.no_sharpen)

    if not args.preview_only:
        os.makedirs(OUT_DIR, exist_ok=True)
        for name, (img, _) in layers.items():
            path = os.path.join(OUT_DIR, name + ".png")
            img.save(path, optimize=False, compress_level=6)
            print(f"  → {path} ({img.mode} {img.width}×{img.height}, {os.path.getsize(path) / 1e6:.1f} МБ)")

    a = render_preview(layers, (0.0, 4.0, CAM_Z))
    b = render_preview(layers, (8.0, 6.0, CAM_Z))
    prev = Image.new("RGB", (a.width, a.height * 2 + 8), (0, 0, 0))
    prev.paste(a, (0, 0))
    prev.paste(b, (0, a.height + 8))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    prev.save(PREVIEW)
    print(f"превью → {PREVIEW} (верх: камера (0,4,20); низ: (8,6,20))")

    print("\nквады для scenes/arena/parallax_background.tscn (QuadMesh.size, position):")
    for name, (_, g) in layers.items():
        print(f"  {name:12s} size = Vector2({g['width_m']:.2f}, {g['height_m']:.2f})  "
              f"position = Vector3(0, {g['y_centre']:.3f}, {g['z']:.1f})  "
              f"[верх y={g['y_top']:.2f}, низ y={g['y_top'] - g['height_m']:.2f}]")


if __name__ == "__main__":
    main()
