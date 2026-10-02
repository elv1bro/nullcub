#!/usr/bin/env python3
"""Текстуры гаража для меню «Гараж + эфир» (docs/plan-demo/MENU_GARAGE.md, референсы docs/refs/menu-garage/).
Без Blender: numpy + Pillow, детерминированно (фиксированные зёрна).

    python3 godot/tools/gen_garage_textures.py          → godot/assets/textures/garage/…

Наборы PBR (тайл = 1 м, бесшовные; цвет задаёт материал Godot через albedo_color, см. scripts/menu/garage_materials.gd):
    paint_metal/  {albedo, roughness, metallic, normal}.png  крашеный металл: светлая краска, сколы до тёмного железа, царапины
    hazard/       {albedo, roughness, normal}.png            жёлто-чёрные полосы 45° (4 на метр) с износом
    tread/        {albedo, roughness, normal}.png            рифлёный стальной лист (ромбы ёлочкой)
    floor/        {albedo, roughness, normal}.png            тёмный бетон-металл пола с пятнами и царапинами
Картинки (не тайлятся):
    rug.png 1024×1536, emblem.png (RGBA), leaves.png (RGBA), blueprint.png, photo_{a..f}.png, poster_{a..c}.png
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, ".."))
OUT = os.path.join(GODOT, "assets", "textures", "garage")
DOC_IMG = os.path.abspath(os.path.join(GODOT, "..", "docs", "plan-demo", "img"))


# ----------------------------------------------------------------------------------------------------------------------
# шум
# ----------------------------------------------------------------------------------------------------------------------
def vnoise(size, cells, seed, octaves=4, gain=0.5):
    """Периодический value-noise (fBm) size×size, 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = rng.random((c, c), dtype=np.float32)
        t = np.linspace(0, c, size, endpoint=False)
        i0 = np.floor(t).astype(int)
        f = t - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % c
        a = g[np.ix_(i0, i0)]
        b = g[np.ix_(i0, i1)]
        cc = g[np.ix_(i1, i0)]
        d = g[np.ix_(i1, i1)]
        fy, fx = f[:, None], f[None, :]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= gain
    return out / tot


def scratches(size, n, seed, length=(0.03, 0.18), width=1):
    """Маска тонких прямых царапин (периодическая)."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (size * 3, size * 3), 0)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.random() * size + size, rng.random() * size + size
        a = rng.random() * math.pi
        L = (length[0] + rng.random() * (length[1] - length[0])) * size
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=int(120 + rng.random() * 135), width=width)
    arr = np.asarray(img, np.float32) / 255.0
    tile = np.zeros((size, size), np.float32)
    for i in range(3):
        for j in range(3):
            tile = np.maximum(tile, arr[i * size:(i + 1) * size, j * size:(j + 1) * size])
    return tile


def normal_from_height(h, strength=2.0):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-gx, gy, np.ones_like(h)], -1)        # OpenGL-нормали (Y вверх), как ждёт Godot
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save_rgb(path, arr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = np.clip(arr, 0, 1) if arr.dtype != np.uint8 else arr
    if a.dtype != np.uint8:
        a = (a * 255 + 0.5).astype(np.uint8)
    Image.fromarray(a).save(path, optimize=True)


def save_gray(path, arr):
    save_rgb(path, np.repeat(np.clip(arr, 0, 1)[..., None], 3, -1))


def lerp(a, b, t):
    return a + (b - a) * t


def col(r, g, b):
    return np.array([r, g, b], np.float32) / 255.0


# ----------------------------------------------------------------------------------------------------------------------
# PBR-наборы
# ----------------------------------------------------------------------------------------------------------------------
def paint_metal(size=1024):
    n1 = vnoise(size, 4, 11, 5)
    n2 = vnoise(size, 16, 12, 4)
    chips = np.clip((vnoise(size, 6, 13, 6, 0.55) - 0.75) * 16.0, 0, 1)        # редкие сколы
    chips = np.maximum(chips, np.clip((vnoise(size, 24, 14, 3) - 0.80) * 10, 0, 1))  # мелкие
    sc = scratches(size, 260, 15)
    paint = lerp(col(232, 228, 218), col(196, 190, 178), n1[..., None] * 0.8)
    paint *= (0.94 + 0.06 * n2[..., None])
    iron = lerp(col(70, 66, 62), col(104, 92, 80), n2[..., None])               # не чёрные: после тинта не «пятна коровы»
    rim = np.clip(chips * 3.0, 0, 1) - chips                                       # светлая кромка скола
    alb = lerp(paint, iron, chips[..., None])
    alb = lerp(alb, col(150, 148, 142), (sc * 0.5)[..., None])
    alb += rim[..., None] * 0.06
    rough = np.clip(0.58 + 0.12 * n2 - 0.22 * chips - 0.2 * sc, 0, 1)
    metal = np.clip(chips * 0.8 + sc * 0.5, 0, 1)
    h = 1.0 - chips * 0.8 - sc * 0.15 + n1 * 0.05
    d = os.path.join(OUT, "paint_metal")
    save_rgb(os.path.join(d, "albedo.png"), alb)
    save_gray(os.path.join(d, "roughness.png"), rough)
    save_gray(os.path.join(d, "metallic.png"), metal)
    save_rgb(os.path.join(d, "normal.png"), normal_from_height(h, 6.0))


def hazard(size=1024):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    stripe = ((x + y) * 4.0) % 1.0 < 0.5
    n1 = vnoise(size, 5, 21, 5)
    chips = np.clip((vnoise(size, 8, 22, 6, 0.55) - 0.64) * 12.0, 0, 1)
    dirt = vnoise(size, 3, 23, 4)
    yellow = lerp(col(226, 168, 30), col(190, 130, 22), n1[..., None])
    black = lerp(col(22, 21, 20), col(40, 38, 34), n1[..., None])
    alb = np.where(stripe[..., None], yellow, black)
    alb = lerp(alb, col(70, 66, 60), chips[..., None] * 0.85)
    alb *= (0.8 + 0.2 * dirt[..., None])
    rough = np.clip(0.55 + 0.15 * n1 - 0.15 * chips, 0, 1)
    h = 1.0 - chips * 0.7 + n1 * 0.05
    d = os.path.join(OUT, "hazard")
    save_rgb(os.path.join(d, "albedo.png"), alb)
    save_gray(os.path.join(d, "roughness.png"), rough)
    save_rgb(os.path.join(d, "normal.png"), normal_from_height(h, 5.0))


def tread(size=1024):
    """Рифлёный лист: 8 × 8 ромбов на метр, соседние — повёрнуты (ёлочка)."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    cells = 8
    cx, cy = (x * cells) % 1.0 - 0.5, (y * cells) % 1.0 - 0.5
    ix, iy = np.floor(x * cells), np.floor(y * cells)
    flip = ((ix + iy) % 2 == 0)
    a = np.where(flip, 1.0, -1.0) * math.radians(45)
    u = cx * np.cos(a) - cy * np.sin(a)
    v = cx * np.sin(a) + cy * np.cos(a)
    bump = np.clip(1.0 - np.sqrt((u / 0.36) ** 2 + (v / 0.09) ** 2), 0, 1)
    bump = np.clip(bump * 3.0, 0, 1)
    n1 = vnoise(size, 6, 31, 5)
    sc = scratches(size, 200, 32)
    base = lerp(col(92, 94, 98), col(64, 64, 66), n1[..., None])
    alb = lerp(base, col(150, 150, 150), (bump * 0.35)[..., None])
    alb = lerp(alb, col(170, 168, 160), (sc * 0.4)[..., None])
    rough = np.clip(0.5 + 0.2 * n1 - 0.25 * bump - 0.2 * sc, 0, 1)
    d = os.path.join(OUT, "tread")
    save_rgb(os.path.join(d, "albedo.png"), alb)
    save_gray(os.path.join(d, "roughness.png"), rough)
    save_rgb(os.path.join(d, "normal.png"), normal_from_height(bump * 0.6 + n1 * 0.05, 8.0))


def floor(size=1024):
    n1 = vnoise(size, 3, 41, 6)
    n2 = vnoise(size, 12, 42, 4)
    stains = np.clip((vnoise(size, 4, 43, 5) - 0.55) * 4, 0, 1)
    sc = scratches(size, 160, 44, (0.02, 0.1))
    alb = lerp(col(58, 57, 58), col(36, 35, 37), n1[..., None])
    alb *= (0.9 + 0.1 * n2[..., None])
    alb = lerp(alb, col(24, 20, 18), stains[..., None] * 0.6)
    alb = lerp(alb, col(110, 108, 104), (sc * 0.35)[..., None])
    rough = np.clip(0.72 + 0.1 * n2 - 0.25 * stains - 0.15 * sc, 0, 1)
    d = os.path.join(OUT, "floor")
    save_rgb(os.path.join(d, "albedo.png"), alb)
    save_gray(os.path.join(d, "roughness.png"), rough)
    save_rgb(os.path.join(d, "normal.png"), normal_from_height(n2 * 0.3 + n1 * 0.2 - sc * 0.1, 3.0))


# ----------------------------------------------------------------------------------------------------------------------
# картинки
# ----------------------------------------------------------------------------------------------------------------------
CREAM = (232, 220, 196)


def emblem_draw(d, cx, cy, r, fill, width):
    """Эмблема лиги (предложение): кольцо, 12 зубцов, купол-полусфера и фигурка бойца в нём."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=fill, width=width)
    ri = r * 0.78
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], outline=fill, width=max(2, width // 2))
    for k in range(12):
        a = 2 * math.pi * k / 12
        x0, y0 = cx + math.cos(a) * ri, cy + math.sin(a) * ri
        x1, y1 = cx + math.cos(a) * (r - width * 0.5), cy + math.sin(a) * (r - width * 0.5)
        d.line([(x0, y0), (x1, y1)], fill=fill, width=max(2, width // 2))
    rd = r * 0.5
    d.arc([cx - rd, cy - rd * 0.8, cx + rd, cy + rd * 1.2], 180, 360, fill=fill, width=width)
    d.line([(cx - rd * 1.1, cy + rd * 0.2), (cx + rd * 1.1, cy + rd * 0.2)], fill=fill, width=width)
    hr = r * 0.07
    d.ellipse([cx - hr, cy - rd * 0.55 - hr, cx + hr, cy - rd * 0.55 + hr], fill=fill)
    d.line([(cx, cy - rd * 0.45), (cx, cy - rd * 0.05)], fill=fill, width=max(2, width // 2))
    d.line([(cx - rd * 0.3, cy - rd * 0.35), (cx + rd * 0.3, cy - rd * 0.2)], fill=fill, width=max(2, width // 2))


def emblem(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    emblem_draw(d, size / 2, size / 2, size * 0.42, CREAM + (255,), int(size * 0.045))
    # износ ткани: дырявим альфу шумом
    n = vnoise(size, 8, 51, 4)
    a = np.asarray(img).copy()
    a[..., 3] = (a[..., 3].astype(np.float32) * np.clip((n - 0.18) * 3.0, 0, 1)).astype(np.uint8)
    Image.fromarray(a).save(os.path.join(OUT, "emblem.png"), optimize=True)


def rug(w=1536, h=1024):
    rng = np.random.default_rng(61)
    base = Image.new("RGB", (w, h), (112, 24, 22))
    d = ImageDraw.Draw(base)
    m = 46
    for i, (c, wd) in enumerate([((60, 14, 14), 30), (CREAM, 10), ((150, 40, 30), 26), (CREAM, 6)]):
        d.rectangle([m + i * 28, m + i * 28, w - m - i * 28, h - m - i * 28], outline=c, width=wd)
    for k in range(18):           # «ёлочка» по кайме
        x = 190 + k * (w - 380) / 17
        for y in (100, h - 100):
            d.polygon([(x - 22, y), (x, y - 18), (x + 22, y), (x, y + 18)], outline=CREAM, width=4)
    emblem_draw(d, w / 2, h / 2, h * 0.26, (160, 58, 44), 14)
    arr = np.asarray(base, np.float32) / 255.0
    n = vnoise(1536, 6, 62, 5)[:h, :w]
    fib = vnoise(1536, 96, 63, 2)[:h, :w]
    arr *= (0.78 + 0.3 * n[..., None]) * (0.92 + 0.12 * fib[..., None])
    arr = lerp(arr, col(80, 60, 50), np.clip((vnoise(1536, 3, 64, 4)[:h, :w] - 0.6) * 2, 0, 1)[..., None] * 0.5)
    save_rgb(os.path.join(OUT, "rug.png"), arr)
    save_rgb(os.path.join(OUT, "rug_normal.png"), normal_from_height(fib * 0.5 + n * 0.2, 2.0))


def leaves(size=512):
    """Плющ: 40 трёхлопастных листьев разных оттенков на прозрачном фоне."""
    rng = np.random.default_rng(71)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(46):
        cx, cy = rng.random() * size * 0.86 + size * 0.07, rng.random() * size * 0.86 + size * 0.07
        s = size * (0.045 + rng.random() * 0.04)
        a = rng.random() * 2 * math.pi
        g = (int(40 + rng.random() * 40), int(80 + rng.random() * 60), int(28 + rng.random() * 30), 255)
        pts = []
        for k in range(30):
            t = 2 * math.pi * k / 30
            rr = s * (0.62 + 0.38 * abs(math.cos(1.5 * t)))
            pts.append((cx + rr * math.cos(t + a), cy + rr * math.sin(t + a)))
        d.polygon(pts, fill=g)
        d.line([(cx, cy), (cx + s * math.cos(a), cy + s * math.sin(a))], fill=(g[0] + 30, g[1] + 40, g[2] + 20, 255), width=2)
    img.save(os.path.join(OUT, "leaves.png"), optimize=True)


def blueprint(w=1024, h=704):
    img = Image.new("RGB", (w, h), (34, 70, 120))
    d = ImageDraw.Draw(img)
    line = (196, 220, 240)
    faint = (70, 110, 160)
    for x in range(0, w, 32):
        d.line([(x, 0), (x, h)], fill=faint, width=1)
    for y in range(0, h, 32):
        d.line([(0, y), (w, y)], fill=faint, width=1)
    cx, cy = w * 0.42, h * 0.52
    # боец с круглым корпусом (бочка-ядро), коробка-голова, конечности с шарнирами
    d.ellipse([cx - 120, cy - 110, cx + 120, cy + 110], outline=line, width=5)
    d.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], outline=line, width=3)
    d.rectangle([cx - 60, cy - 230, cx + 60, cy - 130], outline=line, width=5)
    d.rectangle([cx - 38, cy - 210, cx + 38, cy - 156], outline=line, width=2)
    for s in (-1, 1):
        sx = cx + s * 120
        d.ellipse([sx - 16, cy - 76, sx + 16, cy - 44], outline=line, width=3)
        d.line([(sx + s * 10, cy - 60), (sx + s * 90, cy + 10)], fill=line, width=10)
        d.ellipse([sx + s * 90 - 14, cy - 4, sx + s * 90 + 14, cy + 24], outline=line, width=3)
        d.line([(sx + s * 92, cy + 20), (sx + s * 110, cy + 120)], fill=line, width=9)
        d.rectangle([sx + s * 110 - 22, cy + 120, sx + s * 110 + 22, cy + 160], outline=line, width=3)
        hx = cx + s * 55
        d.ellipse([hx - 16, cy + 96, hx + 16, cy + 128], outline=line, width=3)
        d.line([(hx, cy + 126), (hx + s * 20, cy + 230)], fill=line, width=12)
        d.rectangle([hx + s * 20 - 34, cy + 228, hx + s * 20 + 34, cy + 252], outline=line, width=3)
    # размерные линии и «надписи» штрихами
    d.line([(cx + 190, cy - 230), (cx + 190, cy + 252)], fill=line, width=2)
    for yy in (cy - 230, cy + 252):
        d.line([(cx + 178, yy), (cx + 202, yy)], fill=line, width=2)
    rng = np.random.default_rng(81)
    for blk in range(7):
        bx, by = (w * 0.72, 60 + blk * 82) if blk < 6 else (40, h - 110)
        for k in range(3):
            L = 60 + rng.random() * 140
            d.line([(bx, by + k * 14), (bx + L, by + k * 14)], fill=line, width=3)
    d.rectangle([w - 300, h - 120, w - 30, h - 30], outline=line, width=3)
    d.line([(w - 300, h - 75), (w - 30, h - 75)], fill=line, width=2)
    arr = np.asarray(img, np.float32) / 255.0
    n = vnoise(1024, 5, 82, 5)[:h, :w]
    yy, xx = np.mgrid[0:h, 0:w]
    vig = 1.0 - 0.35 * (((xx / w - 0.5) * 2) ** 4 + ((yy / h - 0.5) * 2) ** 4)
    arr *= (0.82 + 0.25 * n[..., None]) * vig[..., None]
    save_rgb(os.path.join(OUT, "blueprint.png"), arr)


def _paper_frame(im, border=10, tone=(236, 226, 204)):
    im = ImageOps.expand(im, border=border, fill=tone)
    return ImageOps.expand(im, border=(0, 0, 0, border * 3), fill=tone)


PHOTOS = [("00-void-v7-fight.png", None), ("00-void-v6-ko.png", None), ("body-paint-arena.png", (300, 80, 1500, 980)),
          ("00-playground-v5-fight.png", None), ("body-kit-v1-presets.png", None), ("00-workshop-v5-ko.png", None)]
POSTERS = [("body-paint-arena.png", (560, 0, 1280, 1080), (190, 60, 40)),
           ("scrap-parallax-godot-v2a.png", (600, 0, 1320, 1080), (40, 80, 120)),
           ("05-void-v6-wide.png", None, (110, 60, 150))]


def photos():
    for i, (fn, box) in enumerate(PHOTOS):
        p = os.path.join(DOC_IMG, fn)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        if box:
            im = im.crop(box)
        im = ImageOps.fit(im, (320, 240))
        g = ImageOps.grayscale(im)
        sep = ImageOps.colorize(ImageOps.autocontrast(g, cutoff=2), (40, 28, 18), (238, 222, 190))
        _paper_frame(sep).save(os.path.join(OUT, "photo_%s.png" % "abcdef"[i]), optimize=True)


def posters():
    for i, (fn, box, tint) in enumerate(POSTERS):
        p = os.path.join(DOC_IMG, fn)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        if box:
            im = im.crop(box)
        im = ImageOps.fit(im, (384, 560))
        im = im.filter(ImageFilter.GaussianBlur(1.2)).quantize(12).convert("RGB")      # «печать»
        arr = np.asarray(im, np.float32) / 255.0
        arr = lerp(arr, np.array(tint, np.float32) / 255.0, 0.25)
        im = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 470, 384, 560], fill=(28, 24, 20))
        d.rectangle([18, 488, 366, 512], fill=CREAM)
        d.rectangle([18, 522, 250, 538], fill=tint)
        _paper_frame(im, 12).save(os.path.join(OUT, "poster_%s.png" % "abc"[i]), optimize=True)


def banner(w=512, h=832):
    """Флаг лиги: красная ткань с переплетением, кремовая кайма и эмблема (UV 0..1 модели Garage_Banner)."""
    img = Image.new("RGB", (w, h), (128, 22, 20))
    d = ImageDraw.Draw(img)
    d.rectangle([14, 14, w - 14, h - 14], outline=CREAM, width=8)
    emblem_draw(d, w / 2, h * 0.42, w * 0.32, CREAM, 18)
    arr = np.asarray(img, np.float32) / 255.0
    yy, xx = np.mgrid[0:h, 0:w]
    weave = 0.93 + 0.07 * ((np.sin(xx * 1.6) * np.sin(yy * 1.6)) > 0)
    n = vnoise(1024, 6, 91, 5)[:h, :w]
    arr *= weave[..., None] * (0.8 + 0.3 * n[..., None])
    save_rgb(os.path.join(OUT, "banner.png"), arr)


TV = [("tv_live_a.png", "body-paint-arena.png", None), ("tv_live_b.png", "00-void-v7-fight.png", None),
      ("tv_live_c.png", "00-playground-v5-fight.png", None), ("tv_live_d.png", "body-kit-v1-arena.png", None),
      ("tv_replay.png", "00-void-v7-ko.png", None), ("tv_quick.png", "scrap-parallax-godot-v2a.png", None),
      ("tv_opponent.png", "body-kit-v1.png", (1095, 245, 1335, 560)), ("tv_build.png", "body-kit-v1.png", (470, 245, 710, 560))]


def tv_images():
    """Кадры для эфира на телевизоре (TV-канал меню): 768 px по ширине, вырезки бойцов из листа кита — 240×315."""
    for out, fn, box in TV:
        p = os.path.join(DOC_IMG, fn)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        if box:
            im = im.crop(box)
        else:
            im = ImageOps.fit(im, (768, 432))
        im.save(os.path.join(OUT, "tv", out), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(OUT, "tv"), exist_ok=True)
    banner()
    tv_images()
    paint_metal()
    hazard()
    tread()
    floor()
    emblem()
    rug()
    leaves()
    blueprint()
    photos()
    posters()
    for root, _, files in os.walk(OUT):
        for f in sorted(files):
            if f.endswith(".png"):
                p = os.path.join(root, f)
                print("%-60s %8d" % (os.path.relpath(p, GODOT), os.path.getsize(p)))


if __name__ == "__main__":
    main()
