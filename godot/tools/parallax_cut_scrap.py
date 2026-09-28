#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Резка листа THE SCRAP (docs/refs/biomes/01-scrap/parallax.png, 1536×1024) на слои параллакса биома 1 «Свалка».

Лист: слева подписи, справа пять полос ~1362 × 90–116 пкс (LAYER 0 SKY, 1 FAR TOWERS, 2 MID STRUCTURES,
3 NEAR SCRAP, 4 FOREGROUND), внизу COMBINED BACKGROUND и GAMEPLAY EXAMPLE. Полосы находятся автоматически
(find_bands: тёмные строки-разделители + тёмные поля слева/справа).

Выход — godot/assets/textures/parallax/scrap/ (имена как у фона «Руин», узлы сцены те же):
  layer4_sky.png   RGB   ← LAYER 0 SKY: кроп правой части полосы (закат, одно солнце — второе, лишнее, закрашено
                         инпейнтом), сверху дорисован зенит, снизу — тёплая дымка горизонта; закрывает весь кадр
  layer3_far.png   RGBA  ← LAYER 1 FAR TOWERS: небо вырезано в alpha, мелкие островки (птицы, мусор) убраны, шпили
                         у среза полосы растворены; нижняя четверть полосы (туман у подножий) растворяется в дымку,
                         непрозрачна и продолжена вниз сгущающейся дымкой до низа кадра
  layer2_mid.png   RGBA  ← LAYER 2 MID STRUCTURES: небо, солнце и светлая дымка с дальними башнями (дубль слоя 3)
                         вырезаны; нижняя половина полосы плотная (своя нарисованная дымка), самый низ растворяется
                         в сумеречную дымку — непрозрачно — и ею же продолжен до низа кадра (линия земли под полом)
  layer1_fore.png  RGBA  ← LAYER 4 FOREGROUND: только нижние 64 строки полосы (хлам/шестерни/цепи), верх — в
                         прозрачность, низ сплошной и продолжен тёмной пятнистой тенью до низа кадра
Превью в перспективе, как из камеры игры (fov 45, две позиции): docs/plan-demo/img/scrap-parallax-v1.png

LAYER 3 NEAR SCRAP сознательно НЕ используется (квада нет):
  • это ближний к бою план — у него самое большое экранное увеличение, а полоса всего ~116 пкс: мыло было бы
    прямо за куклами, где его видно лучше всего;
  • по цвету и тону (коричнево-оранжевые кучи, дерево, латунь) он совпадает с деревянными куклами и платформами —
    читаемость боя падает; подвешенные магниты, цепи и знамёна через всю высоту читаются как интерактив/опасности
    (в ките они и есть механизмы M: Swinging Magnet, Chain Hoist), а тут были бы плоской картинкой;
  • на этом плане по плану волны 1 стоят настоящие 3D-кучи (№001–003, 012–014) со светом и тенью; плоская куча
    рядом с объёмной даёт конфликт параллакса (две «земли» с разной скоростью).
  Между слоем 2 (z −22) и плоскостью боя остаётся место под 3D-декор; дымка слоя 2 закрывает низ, дыр нет.

Запуск: python3 godot/tools/parallax_cut_scrap.py [--preview-only] [--no-sharpen]
Зависимости: Pillow, numpy, scipy, opencv-python (системный /usr/local/bin/python3). Общие утилиты (smoothstep,
дорисовка строк, деконтаминация кромки, проекция квада в кадр) берутся из tools/parallax_cut.py (фон «Руин»).

Что печатает: найденные полосы листа, пиксельные размеры слоёв, запас покрытия кадра и готовый блок размеров/позиций
квадов (метры) для scenes/arena/parallax_scrap.tscn. Геометрия (масштаб м/пкс листа, глубина z, мировая высота
нижней строки кропа) задана в LAYOUT; превью и .tscn считаются из одних и тех же чисел.

Честно про разрешение: полосы по ~90–116 пкс в высоту, а на экране 1080p слой занимает 20–40 % высоты кадра →
увеличение ×3–4 (720p: ×2–2.7). Скрыть это нельзя; смягчено так: апскейл Lanczos до 4096 по ширине, лёгкий
unsharp у ближних слоёв (2 и передний), дальние (небо, башни) чуть размыты до апскейла — читаются как дымка.
Масштабы слоёв подобраны так, чтобы ни один не занимал больше ~40 % кадра (иначе увеличение ×5+). Хуже всего —
передний план при максимальном приближении (z=10: ×5 и больше) и средний план при приближении (×4–5).
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True  # не плодить __pycache__ в tools/ при импорте parallax_cut

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parallax_cut import decontaminate, extend_rows, paste_quad, project, smoothstep, to_img  # noqa: E402

try:
    import cv2
except ImportError:  # инпейнт лишнего солнца — необязателен (есть запасной вариант нормированной свёрткой)
    cv2 = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHEET = os.path.join(ROOT, "docs", "refs", "biomes", "01-scrap", "parallax.png")
OUT_DIR = os.path.join(ROOT, "godot", "assets", "textures", "parallax", "scrap")
PREVIEW = os.path.join(ROOT, "docs", "plan-demo", "img", "scrap-parallax-v1.png")

OUT_WIDTH = 4096
CAM_FOV_DEG = 45.0
ASPECT = 16.0 / 9.0
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)

# Диапазон игровой камеры для арены Свалки (ширина ~40 м по x, пол y=0, платформы до ~8 м). DynamicCamera отъезжает
# по z от ~10 (полувысота кадра 4 м) до ~24 (вся арена) и клэмпит центр по x так, чтобы кадр не вылезал за границы
# арены: |x| ≤ 20 − полуширина кадра на z=0 (16:9) → ±12.6 при z=10, ±2.3 при z=24. Точки ниже — этот клэмп с запасом
# ~0.4 м; по y берём весь диапазон 2.5..10 на любом зуме (это уже с запасом: при полном отъезде центр y ≈ 4..8.5).
# Коробка «±13 по x на любом z» перестраховка вдвое: передний план пришлось бы растянуть до 57 м (×1.5 мыла).
CAM_POINTS = [(sx * ax, cy, cz) for (ax, cz) in ((13.0, 10.0), (8.5, 16.0), (5.5, 20.0), (2.5, 24.0))
              for sx in (-1.0, 1.0) for cy in (2.5, 10.0)]
COVER_MARGIN = 1.5  # м сверх фрустума на плоскости слоя
CAM_A = (0.0, 4.0, 20.0)   # превью и проверки: камера по умолчанию
CAM_B = (11.0, 7.0, 15.0)  # панорама вправо-вверх с приближением

NAMES = ["LAYER 0 SKY", "LAYER 1 FAR TOWERS", "LAYER 2 MID STRUCTURES", "LAYER 3 NEAR SCRAP", "LAYER 4 FOREGROUND"]

# band — индекс полосы листа; x — кроп по x в координатах листа (None = край полосы); rows — кроп строк относительно
# верха полосы (None = вся полоса); z — глубина квада; scale — метров на пиксель ЛИСТА; bottom_y — мировая высота
# нижней строки кропа (до дорисовки); blur — гаусс по листу до апскейла (дымка дальних планов); sharpen — unsharp
# после апскейла (percent, 0 = нет).
#   Небо: облака ≈30 % высоты кадра из камеры A (иначе ×5+), поэтому берётся только ~760 пкс ширины из 1362 —
#   правая часть с закатом; нижняя строка на y=17 → солнце (x≈+49 м) садится за вершины дальних башен.
#   Башни: низ полосы на y=1 (туман прячется за слоем 2), вершины ~21 м (из камеры A это ~80 % высоты кадра).
#   Средний план: линия земли (середина нижнего растворения) на y≈−5.3 при z=−22 → в пересчёте на плоскость боя из
#   камеры A ≈ −0.4 м, т.е. под полом арены; вершины — ~60 % кадра, ниже башен.
#   Передний план: непрозрачная кромка хлама на y≈0.75 при z=+3 → на плоскости боя из камеры A ≈ +0.18 м (ниже
#   щиколоток), кончики шестерней/цепей выше растворяются; ширина 45 м = кадр ±18.2 м при клэмпе камеры + запас.
LAYOUT = {
    "layer4_sky": {"band": 0, "x": (770, None), "z": -100.0, "scale": 0.34, "bottom_y": 17.0,
                   "blur": 0.8, "sharpen": 0, "alpha": False},
    "layer3_far": {"band": 1, "x": (None, None), "z": -50.0, "scale": 0.18, "bottom_y": 1.0,
                   "blur": 0.55, "sharpen": 14, "alpha": True},
    "layer2_mid": {"band": 2, "x": (None, None), "z": -22.0, "scale": 0.13, "bottom_y": -6.55,
                   "blur": 0.0, "sharpen": 30, "alpha": True},
    "layer1_fore": {"band": 4, "x": (None, None), "rows": (34, None), "z": 3.0, "scale": 0.033,
                    "bottom_y": -0.47, "blur": 0.0, "sharpen": 26, "alpha": True},
}
SUN_KEEP_X = 1296          # из двух солнц на полосе неба оставляем правое (крупнее, рядом с дымом); левое ~x1239
SUN_DROP_BOX = (1212, 1266, 183)  # x0, x1, y0 (лист) — где искать лишнее солнце; снизу — до края полосы

# Слой 3 (башни): кей неба = «темнее локальной яркостной огибающей неба» (небо тут от лавандового до
# оранжево-розового — порог по b−r, как у «Руин», не работает); нижняя часть полосы — туман, непрозрачна.
FAR_KEY = (0.035, 0.15)        # smoothstep(огибающая − яркость): от → до
FAR_SOLID = (0.68, 0.92)       # доли высоты полосы: от → до нарастает непрозрачность тумана у подножий
FAR_TOP_FADE = 0.22            # верхние 22 % — в прозрачность (шпили срезаны кромкой полосы — иначе плоские крыши)
SPECK_AREA = 24                # пкс листа: мелкие острова ключа в небе (птицы/мусор/клочки облаков) → убрать
# Слой 2 (средний план): постройки тёмные или подсвечены тёплым; фон (небо, солнце, светлые дальние башни) светлый
# и малонасыщенный → alpha = max(абсолютная темнота, тёплая насыщенность, темнее огибающей), низ полосы плотный.
MID_DARK = (0.28, 0.40)        # 1 − smoothstep(яркость); жёстко — полупрозрачная дымка дала бы серую пелену
MID_WARM = (0.52, 0.72)        # насыщенность тёплых кромок/огня (и r − b > 0.25)
MID_REL = (0.18, 0.28)         # огибающая − яркость
MID_SOLID = (0.30, 0.70)       # доли высоты: ниже ~половины полосы — плотная застройка со своей дымкой; иначе
                               # сквозь щели видна плоская дорисованная дымка слоя 3 (серая пелена с линией)
MID_TOP_FADE = 0.20
MID_BOTTOM_FADE = 0.18         # низ растворяется в сумеречную дымку (непрозрачно) и продолжен ею до низа кадра:
                               # прозрачный низ открывал бы полосу тумана слоя 3 над полом при отъезде камеры
# Передний план: фон полосы — сине-фиолетовая дымка (b > r и не чёрное) → прозрачно; хлам тёмный/тёплый.
FORE_BG = (-0.01, 0.06, 0.13, 0.22)  # smoothstep(b − r) · smoothstep(яркость)
FORE_RAMP = (0.0, 0.42)        # доли высоты кропа: сверху alpha 0 → на 42 % уже 1 (выше — только кончики)
FORE_SOLID = (0.50, 0.72)      # ниже — сплошная куча: просветы дымки между хламом при близкой камере — светлые дыры


# ---------------------------------------------------------------- лист

def find_bands(sheet, x0=200, x1=1520, dark=0.12, frac=0.9):
    """Пять полос слоёв. Строка — разделитель, если ≥ frac колонок x0..x1 темнее dark (по max канала).
    Пробеги не-разделителей: шапка (~113), пять полос (~90–116), большая нижняя панель (~320). Берём пять пробегов
    высотой 80..130 прямо перед первым пробегом выше 200. По x — тёмные поля листа слева/справа от полосы.
    Края полос (антиалиас рамки) срезаются на 2 пкс."""
    v = sheet[:, x0:x1, :].max(axis=2) / 255.0
    is_sep = (v < dark).mean(axis=1) > frac
    runs, y = [], 0
    while y < len(is_sep):
        if is_sep[y]:
            y += 1
            continue
        y0 = y
        while y < len(is_sep) and not is_sep[y]:
            y += 1
        runs.append((y0, y))
    big = next(i for i, (a, b) in enumerate(runs) if b - a > 200)
    bands = [r for r in runs[:big] if 80 <= r[1] - r[0] <= 130][-5:]
    if len(bands) != 5:
        sys.exit(f"ожидал 5 полос, нашёл {bands} (все пробеги {runs})")
    # поля по x — общие для всех полос: колонка-поле тёмная во ВСЕХ полосах сразу (у тёмных полос 3/4 внутри есть
    # почти чёрные колонки цепей, по отдельности граница уехала бы внутрь)
    rows = np.concatenate([np.arange(a, b) for a, b in bands])
    col = (sheet[rows].max(axis=2) / 255.0 < dark).mean(axis=0) > 0.97
    xl = xr = sheet.shape[1] // 2
    while xl > 0 and not col[xl - 1]:
        xl -= 1
    while xr < sheet.shape[1] and not col[xr]:
        xr += 1
    return [(y0 + 2, y1 - 2, xl + 2, xr - 2) for (y0, y1) in bands]


def lum(rgb):
    return rgb @ LUMA


def envelope(rgb, pct=90, size=(7, 81), sigma=(3.0, 10.0)):
    """Локальная «огибающая неба»: высокий перцентиль яркости в широком горизонтальном окне (узкие тёмные башни
    выпадают), сглаженный; и цвет фона той же процедурой по каналам (для деконтаминации кромки)."""
    env = ndimage.gaussian_filter(ndimage.percentile_filter(lum(rgb), pct, size=size), sigma)
    col = np.stack([ndimage.gaussian_filter(ndimage.percentile_filter(rgb[..., c], pct, size=size), sigma)
                    for c in range(3)], axis=2)
    return env, col


def extend_bottom(rgb, n, target_mult, tint, seam_rows=8, blur_x=14.0):
    """Дорисовка n строк снизу с растворением шва в картинку (extend_rows делает это только сверху → переворот)."""
    if n <= 0:
        return rgb
    return extend_rows(rgb[::-1], n, True, target_mult, tint, seam_rows=seam_rows, blur_x=blur_x)[::-1].copy()


def drop_specks(alpha, min_area, keep_from_row, thr=0.4):
    """Мелкие острова alpha (площадь < min_area по порогу thr, целиком выше строки keep_from_row) → 0.
    На полосах это птицы, летящий мусор и клочки облаков: после апскейла ×3–4 они читаются как грязь на небе."""
    lab, n = ndimage.label(alpha > thr, structure=np.ones((3, 3)))
    if n == 0:
        return alpha, 0
    area = ndimage.sum_labels(np.ones_like(alpha), lab, index=np.arange(1, n + 1))
    bottoms = np.array([sl[0].stop for sl in ndimage.find_objects(lab)])
    drop_ids = np.nonzero((area < min_area) & (bottoms < keep_from_row))[0] + 1
    m = np.isin(lab, drop_ids)
    # вместе с полупрозрачным ореолом вокруг острова
    m = ndimage.binary_dilation(m, iterations=2) & ~ndimage.binary_dilation(np.isin(lab, np.setdiff1d(
        np.arange(1, n + 1), drop_ids)), iterations=1)
    out = alpha.copy()
    out[m] = 0.0
    return out, len(drop_ids)


def extend_mottled(rgb, n, target_mult, tint, mottle, sigma, seam_rows=6, blur_x=18.0, seed=11):
    """n строк снизу: градиент extend_bottom + крупные пятна яркости (±mottle, размер sigma = (по y, по x) пкс),
    чтобы дорисованный низ не был плоской заливкой (у тумана — горизонтальные полосы, у хлама — пятна тени).
    Отражение хлама вместо градиента пробовалось — читается как вода/лужа, не годится."""
    if n <= 0:
        return rgb
    H = rgb.shape[0]
    out = extend_bottom(rgb, n, target_mult, tint, seam_rows=seam_rows, blur_x=blur_x)
    rng = np.random.default_rng(seed)
    noise = ndimage.gaussian_filter(rng.normal(0.0, 1.0, (n, rgb.shape[1])).astype(np.float32), sigma)
    noise /= max(float(noise.std()), 1e-6)
    ramp = smoothstep(np.linspace(0.0, 1.0, n, dtype=np.float32), 0.0, 0.3)[:, None]
    out[H:] = np.clip(out[H:] * (1.0 + mottle * noise * ramp)[..., None], 0.0, 1.0)
    return out


def remove_extra_sun(rgb, x_off, y_off):
    """Лишнее (левое) солнце: маска ярких пикселей в SUN_DROP_BOX → инпейнт Telea (или нормированная свёртка)."""
    bx0, bx1, by0 = SUN_DROP_BOX
    H, W = rgb.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    box = (xx + x_off >= bx0) & (xx + x_off < bx1) & (yy + y_off >= by0)
    m = (lum(rgb) > 0.86) & box
    m = ndimage.binary_dilation(m, iterations=3) & box
    if not m.any():
        return rgb, 0
    if cv2 is not None:
        src = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
        out = cv2.inpaint(src[:, :, ::-1], m.astype(np.uint8) * 255, 7, cv2.INPAINT_TELEA)[:, :, ::-1]
        out = out.astype(np.float32) / 255.0
    else:
        w = (~m).astype(np.float32)
        den = ndimage.gaussian_filter(w, 8.0) + 1e-4
        out = rgb.copy()
        for c in range(3):
            out[..., c] = np.where(m, ndimage.gaussian_filter(rgb[..., c] * w, 8.0) / den, rgb[..., c])
    # лёгкое размытие заплатки, чтобы не было «пластилина» Telea
    soft = ndimage.gaussian_filter(m.astype(np.float32), 2.0)[..., None]
    out = out * (1.0 - soft) + ndimage.gaussian_filter(out, (2.0, 2.0, 0.0)) * soft
    return out, int(m.sum())


def upscale(arr, width, sharpen_pct):
    img = to_img(arr)
    h = int(round(img.height * width / img.width))
    img = img.resize((width, h), Image.LANCZOS)
    if sharpen_pct > 0:
        if img.mode == "RGBA":
            rgb = img.convert("RGB").filter(ImageFilter.UnsharpMask(radius=2.5, percent=sharpen_pct, threshold=2))
            img = Image.merge("RGBA", (*rgb.split(), img.split()[3]))
        else:
            img = img.filter(ImageFilter.UnsharpMask(radius=2.5, percent=sharpen_pct, threshold=2))
    return img


def view_extent(z):
    """Объединение видимых прямоугольников камер CAM_POINTS на глубине z: (x0, y0, x1, y1)."""
    xs, ys = [], []
    for cx, cy, cz in CAM_POINTS:
        hh = math.tan(math.radians(CAM_FOV_DEG / 2.0)) * (cz - z)
        xs += [cx - hh * ASPECT, cx + hh * ASPECT]
        ys += [cy - hh, cy + hh]
    return min(xs), min(ys), max(xs), max(ys)


# ---------------------------------------------------------------- слои

def build_layers(sheet, bands, sharpen=True):
    """→ dict name → (PIL image, geometry). Геометрия в метрах: width_m, height_m, y_top, y_centre, z."""
    out = {}
    for name, cfg in LAYOUT.items():
        by0, by1, bx0, bx1 = bands[cfg["band"]]
        x0 = cfg["x"][0] if cfg["x"][0] is not None else bx0
        x1 = cfg["x"][1] if cfg["x"][1] is not None else bx1
        y0, y1 = by0, by1
        if cfg.get("rows"):
            r0, r1 = cfg["rows"]
            y0 = by0 + r0
            y1 = by1 if r1 is None else by0 + r1
        rgb = sheet[y0:y1, x0:x1, :].astype(np.float32) / 255.0
        H, W = rgb.shape[:2]
        s = cfg["scale"]
        alpha = None
        top_ext = bottom_ext = 0
        vx0, vy0, vx1, vy1 = view_extent(cfg["z"])
        info = ""

        if name == "layer4_sky":
            rgb, n_sun = remove_extra_sun(rgb, x0, y0)
            if cfg["blur"] > 0:
                rgb = ndimage.gaussian_filter(rgb, (cfg["blur"], cfg["blur"], 0.0))
            # закрыть фрустум по высоте: сверху зенит (темнее и синее), снизу тёплая дымка горизонта
            top_ext = max(0, int(math.ceil((vy1 + COVER_MARGIN - (cfg["bottom_y"] + H * s)) / s)))
            bottom_ext = max(0, int(math.ceil((cfg["bottom_y"] - (vy0 - COVER_MARGIN)) / s)))
            rgb = extend_rows(rgb, top_ext, True, 0.80, (0.78, 0.86, 1.08), seam_rows=8, blur_x=30.0)
            rgb = extend_bottom(rgb, bottom_ext, 0.92, (1.04, 0.92, 0.88), seam_rows=6, blur_x=40.0)
            info = f"инпейнт лишнего солнца {n_sun} пкс"

        elif name == "layer3_far":
            if cfg["blur"] > 0:
                rgb = ndimage.gaussian_filter(rgb, (cfg["blur"], cfg["blur"], 0.0))
            env, env_rgb = envelope(rgb)
            key = smoothstep(env - lum(rgb), *FAR_KEY)
            rows = np.arange(H, dtype=np.float32) / H
            solid = smoothstep(rows, *FAR_SOLID)[:, None]
            top = smoothstep(rows, 0.0, FAR_TOP_FADE)[:, None]
            key, n_sp = drop_specks(key, SPECK_AREA, int(H * FAR_SOLID[0]))
            alpha = np.maximum(key, solid)
            rgb = decontaminate(rgb, alpha, env_rgb)  # по ключу, до растворения верха (иначе кромка «горит»)
            alpha = alpha * top
            info = f"прозрачно (a<0.1) {100.0 * (alpha < 0.1).mean():.1f} % полосы, убрано островков {n_sp}"
            # туман у подножий продолжен вниз, сгущаясь и темнея к земле (кадр снизу закрыт до vy0)
            bottom_ext = max(0, int(math.ceil((cfg["bottom_y"] - (vy0 - COVER_MARGIN)) / s)))
            rgb = extend_mottled(rgb, bottom_ext, 0.62, (0.95, 0.90, 1.02), 0.06, (3.0, 40.0), seam_rows=28,
                                 blur_x=30.0)
            alpha = np.concatenate([alpha, np.ones((bottom_ext, W), dtype=np.float32)], axis=0)

        elif name == "layer2_mid":
            env, env_rgb = envelope(rgb)
            L = lum(rgb)
            mx, mn = rgb.max(axis=2), rgb.min(axis=2)
            sat = (mx - mn) / np.maximum(mx, 1e-3)
            a_dark = 1.0 - smoothstep(L, *MID_DARK)
            a_warm = smoothstep(sat, *MID_WARM) * smoothstep(rgb[..., 0] - rgb[..., 2], 0.25, 0.40)
            a_rel = smoothstep(env - L, *MID_REL)
            key = np.maximum(np.maximum(a_dark, a_warm), a_rel)
            key, n_sp = drop_specks(key, SPECK_AREA, int(H * MID_SOLID[0]))
            rows = np.arange(H, dtype=np.float32) / H
            solid = smoothstep(rows, *MID_SOLID)[:, None]
            top = smoothstep(rows, 0.0, MID_TOP_FADE)[:, None]
            bot = smoothstep((1.0 - rows), 0.0, MID_BOTTOM_FADE)[:, None]
            alpha = np.maximum(key, solid)
            rgb = decontaminate(rgb, alpha, env_rgb)
            alpha = alpha * top
            # низ: цвет к сумеречной дымке (половина — тёмный хлам низа полосы, половина — притемнённая светлая дымка
            # огибающей), непрозрачно; дальше та же дымка, темнея, до низа кадра (vy0) — полосы тумана над полом нет
            haze = 0.5 * rgb[-10:].reshape(-1, 3).mean(axis=0) \
                + 0.5 * 0.6 * env_rgb[int(H * 0.66):].reshape(-1, 3).mean(axis=0)
            w = 0.85 * (1.0 - bot[..., None])
            rgb = rgb * (1.0 - w) + haze[None, None, :] * w
            alpha = np.maximum(alpha, 1.0 - bot)
            bottom_ext = max(0, int(math.ceil((cfg["bottom_y"] - (vy0 - COVER_MARGIN)) / s)))
            rgb = extend_mottled(rgb, bottom_ext, 0.7, (0.95, 0.92, 1.0), 0.05, (3.0, 40.0), seam_rows=6,
                                 blur_x=30.0)
            alpha = np.concatenate([alpha, np.ones((bottom_ext, W), dtype=np.float32)], axis=0)
            info = f"прозрачно (a<0.1) {100.0 * (alpha < 0.1).mean():.1f} % полосы, убрано островков {n_sp}"

        elif name == "layer1_fore":
            r, b = rgb[..., 0], rgb[..., 2]
            br0, br1, v0, v1 = FORE_BG
            bg = smoothstep(b - r, br0, br1) * smoothstep(lum(rgb), v0, v1)
            rows = np.arange(H, dtype=np.float32) / H
            ramp = smoothstep(rows, *FORE_RAMP)[:, None]
            solid = smoothstep(rows, *FORE_SOLID)[:, None]
            alpha = np.maximum(ndimage.gaussian_filter(np.clip(1.0 - bg, 0.0, 1.0), 0.7), solid)
            _, env_rgb = envelope(rgb, pct=80)
            rgb = decontaminate(rgb, alpha, env_rgb)  # по ключу, до верхней рампы
            # просветы дымки (в сплошной части) и светлая кайма силуэтов (в полупрозрачной) → тень хлама: локальное
            # среднее не-фона, притемнённое, с весом «фоновости»; иначе при близкой камере это голубые пятна-«дыры»
            wj = (1.0 - bg).astype(np.float32)
            den = ndimage.gaussian_filter(wj, 6.0) + 1e-4
            fill = np.stack([ndimage.gaussian_filter(rgb[..., c] * wj, 6.0) / den for c in range(3)], axis=2) * 0.6
            k = np.clip(bg * (0.6 + 0.4 * solid), 0.0, 1.0)[..., None]
            rgb = rgb * (1.0 - k) + fill * k
            alpha = alpha * ramp
            bottom_ext = max(0, int(math.ceil((cfg["bottom_y"] - (vy0 - COVER_MARGIN)) / s)))
            rgb = extend_mottled(rgb, bottom_ext, 0.40, (1.0, 0.90, 0.92), 0.12, (5.0, 16.0), seam_rows=22)
            alpha = np.concatenate([alpha, np.ones((bottom_ext, W), dtype=np.float32)], axis=0)
            info = f"непрозрачная кромка (a≥0.9) с {100.0 * FORE_RAMP[1]:.0f} % высоты кропа"

        arr = rgb if alpha is None else np.concatenate([rgb, alpha[..., None]], axis=2)
        img = upscale(arr, OUT_WIDTH, cfg["sharpen"] if sharpen else 0)
        rows_total, cols_total = arr.shape[:2]
        geom = {
            "z": cfg["z"], "width_m": cols_total * s, "height_m": rows_total * s,
            "y_top": cfg["bottom_y"] + (H + top_ext) * s, "crop": (x0, y0, x1, y1),
            "top_ext": top_ext, "bottom_ext": bottom_ext, "view": (vx0, vy0, vx1, vy1),
        }
        geom["y_bottom"] = geom["y_top"] - geom["height_m"]
        geom["y_centre"] = geom["y_top"] - geom["height_m"] / 2.0
        if name == "layer4_sky":
            geom["sun_x"] = (SUN_KEEP_X - (x0 + x1) / 2.0) * s
        if name == "layer2_mid":
            geom["ground_y"] = cfg["bottom_y"] + H * MID_BOTTOM_FADE * 0.5 * s
        if name == "layer1_fore":
            geom["opaque_top_y"] = cfg["bottom_y"] + H * (1.0 - FORE_RAMP[1]) * s
        out[name] = (img, geom)
        mx = min(geom["width_m"] / 2.0 - max(-vx0, vx1),
                 (geom["y_top"] - vy1) if name == "layer4_sky" else 99.0,
                 vy0 - geom["y_bottom"])
        print(f"  {name}: {NAMES[cfg['band']]} кроп x{x0}..{x1} y{y0}..{y1} ({W}×{H}) → {cols_total}×{rows_total} "
              f"пкс листа (верх +{top_ext}, низ +{bottom_ext}) → {img.width}×{img.height}; {info}; "
              f"запас покрытия {mx:.1f} м")
    return out


# ---------------------------------------------------------------- превью

def render_preview(layers, cam, size=(1280, 720)):
    canvas = Image.new("RGBA", size, (60, 50, 80, 255))
    for name in ("layer4_sky", "layer3_far", "layer2_mid"):
        img, g = layers[name]
        x0, y0, x1, y1, _ = project(cam, g["z"], g["y_centre"], g["width_m"], g["height_m"], size)
        paste_quad(canvas, img, (x0, y0, x1, y1))
    # плоскость боя z=0: пол арены (верх y=0, 40 м), платформы до 8 м и две куклы 1.8 м — для масштаба
    d = ImageDraw.Draw(canvas)
    x0, y0, x1, y1, s = project(cam, 0.0, -1.5, 40.0, 3.0, size)
    d.rectangle([x0, y0, x1, y1], fill=(74, 58, 46, 255))
    for (px, py, pw) in ((-10.0, 3.0, 5.0), (8.0, 4.5, 6.0), (-2.0, 6.5, 4.0), (13.0, 8.0, 4.0)):
        qx0, qy0, qx1, qy1, _ = project(cam, 0.0, py - 0.3, pw, 0.6, size)
        d.rectangle([qx0 + px * s, qy0, qx1 + px * s, qy1], fill=(96, 72, 52, 255), outline=(40, 28, 20, 255))
    for dx in (-1.5, 1.5):
        hx0, hy0, hx1, hy1, _ = project(cam, 0.0, 0.9, 0.5, 1.8, size)
        d.rectangle([hx0 + dx * s, hy0, hx1 + dx * s, hy1], fill=(214, 170, 110, 255), outline=(60, 40, 20, 255))
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
    bands = find_bands(sheet)
    for n, (y0, y1, x0, x1) in zip(NAMES, bands):
        print(f"  полоса {n}: строки {y0}..{y1 - 1}, колонки {x0}..{x1 - 1} ({x1 - x0}×{y1 - y0})")
    print("  LAYER 3 NEAR SCRAP не режется (см. docstring: ближний план под 3D-кучи)")
    print("слои:")
    layers = build_layers(sheet, bands, sharpen=not args.no_sharpen)

    if not args.preview_only:
        os.makedirs(OUT_DIR, exist_ok=True)
        for name, (img, _) in layers.items():
            path = os.path.join(OUT_DIR, name + ".png")
            img.save(path, optimize=False, compress_level=6)
            print(f"  → {path} ({img.mode} {img.width}×{img.height}, {os.path.getsize(path) / 1e6:.1f} МБ)")

    a = render_preview(layers, CAM_A)
    b = render_preview(layers, CAM_B)
    prev = Image.new("RGB", (a.width, a.height * 2 + 8), (0, 0, 0))
    prev.paste(a, (0, 0))
    prev.paste(b, (0, a.height + 8))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    prev.save(PREVIEW)
    print(f"превью → {PREVIEW} (верх: камера {CAM_A}; низ: {CAM_B})")

    print("\nквады для scenes/arena/parallax_scrap.tscn (QuadMesh.size, position):")
    for name, (_, g) in layers.items():
        extra = ""
        for k in ("sun_x", "ground_y", "opaque_top_y"):
            if k in g:
                extra += f" {k}={g[k]:.2f}"
        print(f"  {name:12s} size = Vector2({g['width_m']:.2f}, {g['height_m']:.2f})  "
              f"position = Vector3(0, {g['y_centre']:.3f}, {g['z']:.1f})  "
              f"[верх y={g['y_top']:.2f}, низ y={g['y_bottom']:.2f}; кадр x {g['view'][0]:.1f}..{g['view'][2]:.1f}, "
              f"y {g['view'][1]:.1f}..{g['view'][3]:.1f}]{extra}")


if __name__ == "__main__":
    main()
