#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Параллакс Свалки v2: слои из ОТДЕЛЬНЫХ генераций (docs/refs/biomes/01-scrap/parallax-v2/), а не из полос листа.

Почему v2: в v1 (tools/parallax_cut_scrap.py) каждый слой — полоса листа высотой ~100 пкс, на экране 1080p это
увеличение ×3–4 (мыло). Здесь каждый слой — своя картинка 2000×667, и её хватает на весь диапазон камеры арены
при увеличении ≈ ×1.1–1.5 (скрипт печатает таблицу).

Источники (все 2000×667, alpha у присланных webp — фейковая виньетка, игнорируется):
  sky.webp              → layer4_sky.png  RGB   небо целиком; сверху дорисован зенит, снизу — дымка горизонта
  far-towers.webp       → layer3_far.png  RGBA  башни над морем облаков: небо → alpha (темнее огибающей неба), облака
                                                 в небе отброшены (остаются только острова, связанные с основанием),
                                                 второе солнце вырезано; море облаков снизу непрозрачно и продолжено
                                                 вниз темнеющей дымкой до низа кадра
  mid-structures.webp   → layer2_mid.png  RGBA  постройки: фон и бледные «призраки» дальних башен → alpha (тёмное или
                                                 тёплые огни рядом с тёмным), низ растворяется сам (туман источника)
  (генерируется)        → layer2_fog.png  RGBA  полоса тумана перед подножием среднего плана: сверху прозрачно,
                                                 снизу сплошная сумеречная дымка до низа кадра
Передний план пока из v1 (assets/textures/parallax/scrap/layer1_fore.png) — его заменят элементы (docs/plan-demo/
PARALLAX.md).

Геометрия (LAYOUT): z — глубина квада, width_m — ширина картинки источника в метрах (из покрытия фрустума во всём
диапазоне камеры), anchor_y — мировая высота строки anchor_row источника. Печатает блок размеров/позиций квадов для
scenes/arena/parallax_scrap_v2.tscn и таблицу увеличения (экранных пикселей на тексель) при 1080p и 1440p.

Запуск: /usr/local/bin/python3 godot/tools/parallax_cut_scrap_v2.py [--preview-only]
Превью (проекция квадов как из камеры игры, три позиции): docs/plan-demo/img/scrap-parallax-v2-preview.png
"""
import argparse
import json
import math
import os
import sys

sys.dont_write_bytecode = True

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parallax_cut import decontaminate, extend_rows, smoothstep, to_img  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "docs", "refs", "biomes", "01-scrap", "parallax-v2")
OUT_DIR = os.path.join(ROOT, "godot", "assets", "textures", "parallax", "scrap_v2")
FORE_V1 = os.path.join(ROOT, "godot", "assets", "textures", "parallax", "scrap", "layer1_fore.png")
PREVIEW = os.path.join(ROOT, "docs", "plan-demo", "img", "scrap-parallax-v2-preview.png")
TSCN = os.path.join(ROOT, "godot", "scenes", "arena", "parallax_scrap_v2.tscn")

CAM_FOV_DEG = 45.0
ASPECT = 16.0 / 9.0
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)
# Диапазон игровой камеры Свалки — как в tools/parallax_cut_scrap.py и tests/parallax_scrap_snapshot.gd:
# зум z 10..24, центр x клэмпится арены ±20 м, y 2.5..10.
CAM_POINTS = [(sx * ax, cy, cz) for (ax, cz) in ((13.0, 10.0), (8.5, 16.0), (5.5, 20.0), (2.5, 24.0))
              for sx in (-1.0, 1.0) for cy in (2.5, 10.0)]
CAM_A = (0.0, 4.0, 20.0)
CAM_B = (11.0, 7.0, 15.0)
CAM_C = (-13.0, 2.5, 10.0)
CAM_POINTS += [CAM_B, CAM_C]  # кадры снапшот-теста тоже покрыты (B чуть за клэмпом арены)
COVER_MARGIN = 1.5  # м сверх фрустума

# Передний план v1 — те же размеры/позиция, что в parallax_scrap.tscn; в игре арена сдвигает его на layer1_y_offset
# (−1.0 в scrap.tscn) — это учитывает только превью.
FORE_V1_GEOM = {"z": 3.0, "width_m": 44.98, "height_m": 9.37, "y_centre": -3.044}
FORE_ARENA_DY = -1.0

#   Небо: горизонт облаков (строка ~500) чуть ниже кромки моря облаков дальнего слоя — солнце садится за башни.
#   Башни: кромка моря облаков (строка ~450) из камеры A на ~40 % высоты кадра, вершины на ~70 %.
#   Средний план: подножие (строка ~560, где постройки уходят в туман) ниже пола арены из камеры A → основание
#   спрятано за полом и 3D-кучами, вершины на ~70 % кадра (не выше дальних башен — фон не спорит с боем).
LAYOUT = {
    "layer4_sky": {"src": "sky.webp", "z": -100.0, "anchor_row": 500, "anchor_y": -7.9, "ext_top": 260,
                   "ext_bottom": 280, "alpha": False},
    "layer3_far": {"src": "far-towers.webp", "z": -55.0, "anchor_row": 450, "anchor_y": -2.2, "ext_top": 0,
                   "ext_bottom": 260, "alpha": True},
    "layer2_mid": {"src": "mid-structures.webp", "z": -24.0, "anchor_row": 560, "anchor_y": -9.8, "ext_top": 0,
                   "ext_bottom": 0, "alpha": True},
}
# Туман перед подножием среднего плана: квад на z=-20, прозрачный сверху (fog_top_y) → сплошной ниже fog_solid_y,
# продолжен до низа кадра. Цвет — туман источника среднего плана, притемнённый (светлая дымка за куклами-кленами
# ухудшает читаемость; тёмная — «дыра» под ареной).
FOG = {"z": -20.0, "fog_top_y": -1.0, "fog_solid_y": -8.0, "tex": (64, 512)}

SKY_FADE = 150               # строк источника неба, тающих в зенит
# Ключ дальнего слоя: башни темнее локальной огибающей неба; облачное море снизу сплошное.
FAR_KEY = (0.05, 0.17)
FAR_SOLID = (0.60, 0.72)      # доли высоты источника: от → до нарастает непрозрачность моря облаков
FAR_SUN = (0.70, 0.84)        # яркость: ярче — солнце и его ореол → прозрачно (над морем облаков)
FAR_SKY_ROWS = (200, 260)     # выше — только шпили: там оставляем лишь тёмное (облака, прилипшие к башням, → прочь)
FAR_SKY_DARK = (0.26, 0.38)   # 1 − smoothstep(яркость) для этих строк
# Воздушная перспектива (запекается в текстуру): дальше слой → ближе к цвету дымки. Разводит планы по тону, иначе
# башни и средний план одинаково тёмные и глубина читается хуже, чем в v1.
FAR_HAZE = ((0.66, 0.56, 0.70), 0.36)
MID_HAZE = 0.28               # к цвету тумана (×1.35) — средний план светлее 3D-арены перед ним
# Ключ среднего плана: (темнее огибающей) ∧ (тёмное ∨ тёплый огонь рядом с тёмным) — бледные «призраки» уходят.
MID_REL = (0.12, 0.30)
MID_DARK = (0.34, 0.48)       # 1 − smoothstep(яркость)
MID_WARM = (0.45, 0.65)       # насыщенность тёплых огней/знамён (r − b > 0.2), только в 12 пкс от тёмного


def lum(rgb):
    return rgb @ LUMA


def envelope(rgb, pct, size, sigma, down=4):
    """Огибающая фона (высокий перцентиль яркости в широком окне) и её цвет; считается на копии ÷down (быстро)."""
    h, w = rgb.shape[:2]
    small = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).resize((w // down, h // down), Image.BOX),
                       np.float32) / 255.0
    sz = (max(3, size[0] // down), max(3, size[1] // down))
    sg = (sigma[0] / down, sigma[1] / down)

    def up(a):
        return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((w, h), Image.BILINEAR), np.float32)

    env = up(ndimage.gaussian_filter(ndimage.percentile_filter(lum(small), pct, size=sz), sg))
    col = np.stack([up(ndimage.gaussian_filter(ndimage.percentile_filter(small[..., c], pct, size=sz), sg))
                    for c in range(3)], axis=2)
    return env, col


def keep_based(alpha, base_rows, thr=0.45, grow=6):
    """Оставить острова alpha, связанные с основанием (нижние base_rows строк): облака и птицы в небе — отдельно."""
    m = alpha > thr
    m[-base_rows:] = True
    lab, _ = ndimage.label(m, structure=np.ones((3, 3)))
    keep = ndimage.binary_dilation(lab == lab[-1, 0], iterations=grow)
    return alpha * ndimage.gaussian_filter(keep.astype(np.float32), 2.0)


def load(name):
    return np.asarray(Image.open(os.path.join(SRC, name)).convert("RGB"), np.float32) / 255.0


def build_sky():
    """Небо: сверху мягкий зенит, снизу дымка горизонта. Облака верхних SKY_FADE строк источника плавно тают в
    горизонтально однородный градиент (иначе на стыке видна линия и вертикальные полосы от растянутых облаков)."""
    g = LAYOUT["layer4_sky"]
    rgb = load(g["src"])
    h, w = rgb.shape[:2]
    n_top, n_bot = g["ext_top"], g["ext_bottom"]
    top = rgb[:40].reshape(-1, 3)
    l = lum(top)
    zenith = top[l <= np.percentile(l, 8)].mean(axis=0) * np.array([0.80, 0.85, 0.95], np.float32)
    smooth_top = np.stack([ndimage.gaussian_filter(rgb[:SKY_FADE, :, c], (30.0, 500.0), mode="nearest")
                           for c in range(3)], axis=2)
    t = smoothstep(np.arange(SKY_FADE, dtype=np.float32) / SKY_FADE, 0.0, 1.0)[:, None, None]
    rgb = rgb.copy()
    rgb[:SKY_FADE] = smooth_top * (1.0 - t) + rgb[:SKY_FADE] * t
    seam = smooth_top[0]
    u = smoothstep(np.linspace(1.0, 0.0, n_top, dtype=np.float32), 0.0, 1.0)[:, None, None]  # 1 у верха → зенит
    ext_t = seam[None] * (1.0 - u) + zenith[None, None, :] * u
    rgb = np.concatenate([ext_t, rgb], axis=0)
    rgb = extend_rows(rgb[::-1], n_bot, True, 0.85, (1.0, 0.92, 0.95), seam_rows=40, blur_x=420.0)[::-1].copy()
    rng = np.random.default_rng(5)
    rgb[:n_top + SKY_FADE] += rng.normal(0.0, 1.0 / 255.0, rgb[:n_top + SKY_FADE].shape).astype(np.float32)
    return np.clip(rgb, 0.0, 1.0)


def build_far():
    rgb = load(LAYOUT["layer3_far"]["src"])
    h = rgb.shape[0]
    l = lum(rgb)
    env, env_rgb = envelope(rgb, 92, (9, 121), (4, 16))
    a = smoothstep(env - l, *FAR_KEY)
    rows = (np.arange(h, dtype=np.float32) / h)[:, None]
    solid = smoothstep(rows, *FAR_SOLID)
    a = a * (1.0 - smoothstep(l, *FAR_SUN) * (1.0 - solid))  # солнце и ореол над морем облаков
    top = 1.0 - smoothstep(np.arange(h, dtype=np.float32), *FAR_SKY_ROWS)[:, None]
    a = a * (1.0 - top * (1.0 - (1.0 - smoothstep(l, *FAR_SKY_DARK))))
    a = np.maximum(a, solid)
    a = keep_based(a, int(h * 0.3))
    rgb = decontaminate(rgb, a, env_rgb)
    col, k = FAR_HAZE
    rgb = rgb * (1.0 - k) + np.asarray(col, np.float32) * k
    ext = LAYOUT["layer3_far"]["ext_bottom"]
    rgb = extend_rows(rgb[::-1], ext, True, 0.55, (0.92, 0.85, 1.05), seam_rows=12, blur_x=30.0)[::-1].copy()
    a = np.concatenate([a, np.ones((ext, a.shape[1]), np.float32)], axis=0)
    return np.concatenate([rgb, a[..., None]], axis=2)


def build_mid():
    rgb = load(LAYOUT["layer2_mid"]["src"])
    l = lum(rgb)
    env, env_rgb = envelope(rgb, 95, (31, 161), (6, 20))
    rel = smoothstep(env - l, *MID_REL)
    dark = 1.0 - smoothstep(l, *MID_DARK)
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    warm = smoothstep(sat, *MID_WARM) * ((rgb[..., 0] - rgb[..., 2]) > 0.2)
    near_dark = ndimage.maximum_filter((dark > 0.6).astype(np.float32), size=25)
    a = rel * np.maximum(dark, warm * near_dark)
    a = keep_based(a, 3, thr=0.5, grow=3)
    rgb = decontaminate(rgb, a, env_rgb)
    haze = np.clip(fog_colour(env_rgb) * 1.35, 0.0, 1.0)
    rgb = rgb * (1.0 - MID_HAZE) + haze * MID_HAZE
    return np.concatenate([rgb, a[..., None]], axis=2), env_rgb


def fog_colour(mid_env_rgb):
    """Цвет тумана: огибающая фона среднего плана у подножия (строки 560–620), притемнённая и чуть холоднее."""
    c = mid_env_rgb[560:620].reshape(-1, 3).mean(axis=0)
    return np.clip(c * np.array([0.62, 0.60, 0.70], np.float32), 0.0, 1.0)


def build_fog(col):
    w, h = FOG["tex"]
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]  # 0 — верх текстуры (fog_top_y), 1 — низ
    a = smoothstep(t, 0.0, 0.55)
    rng = np.random.default_rng(3)
    n = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), (18, 6), mode="wrap")
    n = n / (np.abs(n).max() + 1e-6)
    a = np.clip(a * (1.0 + 0.25 * n * (1.0 - a)), 0.0, 1.0)
    rgb = np.broadcast_to(col, (h, w, 3)).astype(np.float32) * (1.0 - 0.25 * t[..., None])
    return np.concatenate([rgb, a[..., None]], axis=2)


# ---------------------------------------------------------------- геометрия

def view_extent(z):
    """Мировой прямоугольник, который камера видит на глубине z во всём диапазоне: x0, x1, y0, y1."""
    xs, ys = [], []
    for cx, cy, cz in CAM_POINTS:
        hh = math.tan(math.radians(CAM_FOV_DEG / 2.0)) * (cz - z)
        hw = hh * ASPECT
        xs += [cx - hw, cx + hw]
        ys += [cy - hh, cy + hh]
    return min(xs), max(xs), min(ys), max(ys)


def geometry(name, img_h, src_w):
    g = LAYOUT[name]
    x0, x1, _, _ = view_extent(g["z"])
    width_m = 2.0 * max(-x0, x1) + 2.0 * COVER_MARGIN
    s = width_m / src_w  # м на пиксель
    top_row = -g["ext_top"]  # строка источника у верхнего края текстуры
    bottom_y = g["anchor_y"] - (img_h - g["ext_top"] - g["anchor_row"]) * s  # низ текстуры (с дорисовкой снизу)
    height_m = img_h * s
    return {"z": g["z"], "width_m": round(width_m, 2), "height_m": round(height_m, 2),
            "y_centre": round(bottom_y + height_m / 2.0, 3), "m_per_px": s, "top_row": top_row}


def magnification(g, z, tex_w):
    """Экранных пикселей на тексель при 1080p / 1440p — для ближайшей и дальней точки диапазона камеры."""
    texel_per_m = tex_w / g["width_m"]
    out = {}
    for res in (1080, 1440):
        vals = []
        for (_, _, cz) in CAM_POINTS:
            px_per_m = res / (2.0 * math.tan(math.radians(CAM_FOV_DEG / 2.0)) * (cz - z))
            vals.append(px_per_m / texel_per_m)
        out[res] = (round(min(vals), 2), round(max(vals), 2))
    return out


def project(cam, z, y_centre, w, h, size_px):
    cx, cy, cz = cam
    hh = math.tan(math.radians(CAM_FOV_DEG / 2.0)) * (cz - z)
    s = size_px[1] / 2.0 / hh
    return (size_px[0] / 2.0 + (-w / 2.0 - cx) * s, size_px[1] / 2.0 - (y_centre + h / 2.0 - cy) * s,
            size_px[0] / 2.0 + (w / 2.0 - cx) * s, size_px[1] / 2.0 - (y_centre - h / 2.0 - cy) * s, s)


def paste(canvas, img, rect):
    x0, y0, x1, y1 = rect[:4]
    W, H = canvas.size
    pw, ph = int(round(x1 - x0)), int(round(y1 - y0))
    if pw <= 0 or ph <= 0:
        return
    ox, oy = int(round(x0)), int(round(y0))
    cx0, cy0, cx1, cy1 = max(0, -ox), max(0, -oy), min(pw, W - ox), min(ph, H - oy)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    # ресайз только видимой части (кроп в координатах источника), иначе промежуточные картинки гигантские
    sx, sy = img.width / pw, img.height / ph
    sub = img.resize((cx1 - cx0, cy1 - cy0), Image.BILINEAR, box=(cx0 * sx, cy0 * sy, cx1 * sx, cy1 * sy))
    sub = sub.convert("RGBA")
    canvas.alpha_composite(sub, (ox + cx0, oy + cy0))


def render(layers, cam, size=(1280, 720)):
    from PIL import ImageDraw
    canvas = Image.new("RGBA", size, (255, 0, 255, 255))
    for name in ("layer4_sky", "layer3_far", "layer2_mid", "layer2_fog"):
        img, g = layers[name]
        paste(canvas, img, project(cam, g["z"], g["y_centre"], g["width_m"], g["height_m"], size))
    d = ImageDraw.Draw(canvas)
    x0, y0, x1, y1, s = project(cam, 0.0, -1.5, 40.0, 3.0, size)
    d.rectangle([x0, y0, x1, y1], fill=(70, 50, 38, 255))
    for px, py in ((-10, 3), (8, 4.5), (-2, 6.5), (13, 8)):
        a = project(cam, 0.0, py - 0.3, 5.0, 0.6, size)
        d.rectangle([a[0] + px * s, a[1], a[2] + px * s, a[3]], fill=(80, 58, 42, 255))
    for dx in (-1.5, 1.5):
        a = project(cam, 0.0, 0.9, 0.56, 1.8, size)
        d.rectangle([a[0] + dx * s, a[1], a[2] + dx * s, a[3]], fill=(222, 180, 125, 255))
    img, g = layers["layer1_fore"]
    paste(canvas, img, project(cam, g["z"], g["y_centre"] + FORE_ARENA_DY, g["width_m"], g["height_m"], size))
    return canvas.convert("RGB")


TSCN_HEAD = """[gd_scene format=3 uid="uid://parallaxscrap02"]

[ext_resource type="Script" path="res://scenes/arena/parallax_background.gd" id="1_pbg"]
[ext_resource type="Texture2D" path="res://assets/textures/parallax/scrap_v2/layer4_sky.png" id="2_l4"]
[ext_resource type="Texture2D" path="res://assets/textures/parallax/scrap_v2/layer3_far.png" id="3_l3"]
[ext_resource type="Texture2D" path="res://assets/textures/parallax/scrap_v2/layer2_mid.png" id="4_l2"]
[ext_resource type="Texture2D" path="res://assets/textures/parallax/scrap_v2/layer2_fog.png" id="5_fog"]
[ext_resource type="Texture2D" path="res://assets/textures/parallax/scrap/layer1_fore.png" id="6_l1"]
"""
# узел, ext-id текстуры, прозрачность, метаданные (max_mag — порог резкости снапшот-теста при 1080p, source_px_w —
# ширина источника в пкс: по ней тест считает резкость, а не по ширине текстуры)
TSCN_NODES = [
    ("Layer4Sky", "layer4_sky", "2_l4", False, {"max_mag": 1.6, "source_px_w": 2000}),
    ("Layer3Far", "layer3_far", "3_l3", True, {"max_mag": 1.6, "source_px_w": 2000}),
    ("Layer2Mid", "layer2_mid", "4_l2", True, {"max_mag": 1.6, "ground_play_min": -3.0, "source_px_w": 2000}),
    ("Layer2Fog", "layer2_fog", "5_fog", True, {}),
    ("Layer1Fore", "layer1_fore", "6_l1", True, {"opaque_top_y": 0.75, "source_px_w": 1363}),  # v1: полоса листа
]


def write_tscn(geoms):
    out = [TSCN_HEAD]
    for node, key, tex, alpha, _ in TSCN_NODES:
        out.append('\n[sub_resource type="StandardMaterial3D" id="mat_%s"]\n%sshading_mode = 0\ncull_mode = 2\n'
                   'albedo_texture = ExtResource("%s")\ntexture_repeat = false\ndisable_receive_shadows = true\n'
                   'disable_fog = true\n' % (key, "transparency = 1\n" if alpha else "", tex))
    for node, key, *_ in TSCN_NODES:
        g = geoms[key]
        out.append('\n[sub_resource type="QuadMesh" id="quad_%s"]\nsize = Vector2(%s, %s)\n'
                   % (key, g["width_m"], g["height_m"]))
    out.append('\n[node name="ParallaxScrap" type="Node3D"]\nscript = ExtResource("1_pbg")\nmetadata/source = '
               '"docs/refs/biomes/01-scrap/parallax-v2/ → tools/parallax_cut_scrap_v2.py (сцена генерируется им же); '
               'передний план пока v1, его заменят элементы — docs/plan-demo/PARALLAX.md"\n')
    for node, key, _, _, meta in TSCN_NODES:
        g = geoms[key]
        out.append('\n[node name="%s" type="MeshInstance3D" parent="."]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, %s)\nmaterial_override = '
                   'SubResource("mat_%s")\ncast_shadow = 0\nmesh = SubResource("quad_%s")\n'
                   % (node, g["y_centre"], g["z"], key, key))
        if key == "layer2_mid":
            meta = dict(meta, ground_y=round(LAYOUT["layer2_mid"]["anchor_y"], 2))
        for k, v in meta.items():
            out.append("metadata/%s = %s\n" % (k, v))
    with open(TSCN, "w") as f:
        f.write("".join(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview-only", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    print("небо…", flush=True)
    sky = build_sky()
    print("дальние башни…", flush=True)
    far = build_far()
    print("средний план…", flush=True)
    mid, mid_env = build_mid()
    fog = build_fog(fog_colour(mid_env))

    arrays = {"layer4_sky": sky, "layer3_far": far, "layer2_mid": mid}
    layers, report = {}, {}
    for name, arr in arrays.items():
        g = geometry(name, arr.shape[0], arr.shape[1])
        img = to_img(arr)
        layers[name] = (img, g)
        report[name] = {"px": [arr.shape[1], arr.shape[0]], **{k: g[k] for k in ("z", "width_m", "height_m",
                                                                                   "y_centre")},
                        "magnification": magnification(g, g["z"], arr.shape[1])}
        if not args.preview_only:
            img.save(os.path.join(OUT_DIR, name + ".png"), optimize=True)

    # туман: от fog_top_y до низа кадра на глубине FOG.z
    _, _, vy0, _ = view_extent(FOG["z"])
    fx0, fx1, _, _ = view_extent(FOG["z"])
    fw = 2.0 * max(-fx0, fx1) + 2.0 * COVER_MARGIN
    fbottom = vy0 - COVER_MARGIN
    fh = FOG["fog_top_y"] - fbottom
    # в текстуре alpha доходит до 1 на 55 % высоты — подгоняем, чтобы это было на fog_solid_y
    fh_ramp = (FOG["fog_top_y"] - FOG["fog_solid_y"]) / 0.55
    fh = max(fh, fh_ramp)
    fog_g = {"z": FOG["z"], "width_m": round(fw, 2), "height_m": round(fh, 2),
             "y_centre": round(FOG["fog_top_y"] - fh / 2.0, 3)}
    fog_img = to_img(fog)
    layers["layer2_fog"] = (fog_img, fog_g)
    report["layer2_fog"] = {"px": [fog.shape[1], fog.shape[0]], **fog_g}
    if not args.preview_only:
        fog_img.save(os.path.join(OUT_DIR, "layer2_fog.png"), optimize=True)

    fore = Image.open(FORE_V1).convert("RGBA")
    layers["layer1_fore"] = (fore, FORE_V1_GEOM)

    # покрытие: низ/верх каждого непрозрачного слоя против фрустума
    for name in ("layer4_sky",):
        g = layers[name][1]
        _, _, y0, y1 = view_extent(g["z"])
        report[name]["cover_y"] = {"need": [round(y0, 1), round(y1, 1)],
                                   "have": [round(g["y_centre"] - g["height_m"] / 2, 1),
                                            round(g["y_centre"] + g["height_m"] / 2, 1)]}

    if not args.preview_only:
        write_tscn({k: v[1] for k, v in layers.items()})
        print("сцена:", TSCN)
    frames = [render(layers, c) for c in (CAM_A, CAM_B, CAM_C)]
    sheet = Image.new("RGB", (1280, 720 * 3 + 16), (20, 20, 20))
    for i, f in enumerate(frames):
        sheet.paste(f, (0, i * (720 + 8)))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    sheet.save(PREVIEW)
    print(json.dumps(report, ensure_ascii=False, indent=1))
    print("превью:", PREVIEW)


if __name__ == "__main__":
    main()
