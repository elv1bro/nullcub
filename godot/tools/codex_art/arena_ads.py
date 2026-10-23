#!/usr/bin/env python3
"""Реклама Лиги NULL для щитов арен (23.10.2026; модели — tools/blender/arena_ads.py, расстановка —
scenes/arena/league_boards.gd). Описание и порядок перегенерации — docs/plan-demo/CODEX_ART.md.

    python3 godot/tools/codex_art/arena_ads.py                 # собрать из арта, который уже в репо (docs/steam, гараж)
    python3 godot/tools/codex_art/arena_ads.py --codex DIR     # взять готовые картинки codex из DIR (<id>.png по
                                                               # jobs_arena_ads.json), остальное — сборка как выше

Выход: godot/assets/textures/arena_ads/*.jpg (щиты 16:9 1024×576, LED-ленты 1800×200 ≈ 9:1, изогнутый баннер
2048×344 ≈ 6:1, флаг 512×1000 ≈ 1:2). С --codex и файлом DIR/hero_wide.png ещё кладёт docs/steam/hero_wide.jpg —
его берёт steam_capsules.py для library_hero.

Без codex (лимит до 29.10.2026) щиты собраны здесь: кадры codex из репо + надписи Oswald + нарисованные «товары»
выдуманных спонсоров (шарнир ORBIT JOINTS, ядро VOLTA CORES). Только выдуманные марки; игра — NULL GRAVITY.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
STEAM = os.path.abspath(os.path.join(GODOT, "..", "docs", "steam"))
GARAGE = os.path.join(GODOT, "assets", "textures", "garage")
OUT = os.path.join(GODOT, "assets", "textures", "arena_ads")
FONT = os.path.join(GODOT, "assets", "fonts", "Oswald.ttf")

NAVY = (10, 18, 42)
DEEP = (5, 8, 20)
AMBER = (255, 162, 40)
ORANGE = (255, 140, 51)
CYAN = (90, 220, 255)
CREAM = (242, 230, 206)
WHITE = (255, 255, 255)
RED = (235, 50, 45)

BOARD = (1024, 576)
RIBBON = (1800, 200)
CURVED = (2048, 344)
FLAG = (512, 1000)

# выход → (id задания codex, размер, centering) — если DIR/<id>.png есть, берётся он
CODEX = {
    "board_fight_night": ("ad_fight_night", BOARD, (0.5, 0.5)),
    "board_joints": ("ad_joints", BOARD, (0.5, 0.5)),
    "board_cores": ("ad_cores", BOARD, (0.5, 0.5)),
    "board_nulltv": ("ad_nulltv", BOARD, (0.5, 0.5)),
    "board_scrap_cup": ("ad_scrap_cup", BOARD, (0.5, 0.5)),
    "banner_curved": ("ad_banner_wide", CURVED, (0.5, 0.5)),
    "flag_null": ("ad_vertical", FLAG, (0.5, 0.5)),
}


# ----------------------------------------------------------------------------------------------------------------------
# хелперы
# ----------------------------------------------------------------------------------------------------------------------
def font(px):
    f = ImageFont.truetype(FONT, px)
    try:
        f.set_variation_by_axes([700])     # Oswald — переменный шрифт, жирное начертание
    except Exception:
        pass
    return f


def src(path):
    return Image.open(path).convert("RGB")


def vgrad(size, c0, c1):
    w, h = size
    im = Image.new("RGB", size)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(c0, c1)))
    return im


def radial(size, center, r, c_in, c_out):
    w, h = size
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    steps = 60
    for i in range(steps, 0, -1):
        rr = r * i / steps
        d.ellipse([center[0] - rr, center[1] - rr, center[0] + rr, center[1] + rr], fill=int(255 * (1 - i / steps)))
    m = m.filter(ImageFilter.GaussianBlur(r * 0.05))
    return Image.composite(Image.new("RGB", size, c_in), Image.new("RGB", size, c_out), m)


def side_shade(im, frac=0.6, strength=225, side="left", col=DEEP):
    """Тёмная шторка под надписью."""
    w, h = im.size
    g = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(g)
    for x in range(w):
        t = x / (w * frac) if side == "left" else (w - 1 - x) / (w * frac)
        a = max(0.0, 1.0 - t)
        d.line([(x, 0), (x, h)], fill=int(strength * min(1.0, a * 1.4)))
    return Image.composite(Image.new("RGB", (w, h), col), im, g)


def glow_text(im, xy, text, f, fill, glow=None, radius=10, anchor="la", stroke=0, stroke_fill=None):
    """Надпись с ореолом (glow) поверх im (RGB), xy — точка привязки anchor."""
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=f, fill=fill + (255,), anchor=anchor, stroke_width=stroke,
           stroke_fill=(stroke_fill or fill) + (255,))
    if glow is not None:
        g = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).text(xy, text, font=f, fill=glow + (200,), anchor=anchor, stroke_width=max(2, radius // 3),
                               stroke_fill=glow + (200,))
        g = g.filter(ImageFilter.GaussianBlur(radius))
        im.paste(Image.alpha_composite(im.convert("RGBA"), g).convert("RGB"))
    im.paste(Image.alpha_composite(im.convert("RGBA"), layer).convert("RGB"))
    return d.textbbox(xy, text, font=f, anchor=anchor)


def text_w(text, f):
    b = f.getbbox(text)
    return b[2] - b[0]


def fit_font(text, px, max_w):
    """Oswald не крупнее px и не шире max_w."""
    f = font(px)
    while px > 12 and text_w(text, f) > max_w:
        px -= 4
        f = font(px)
    return f


def stripes(im, col, alpha, spacing, width, slope=0.55, x0=0, x1=None):
    """Диагональные полосы скорости в полосе x0..x1."""
    w, h = im.size
    x1 = w if x1 is None else x1
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for x in range(x0 - h, x1 + h, spacing):
        d.polygon([(x, h), (x + width, h), (x + width + h * slope, 0), (x + h * slope, 0)], fill=col + (alpha,))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rectangle([x0, 0, x1, h], fill=255)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return Image.alpha_composite(im.convert("RGBA"), layer).convert("RGB")


def add_glow(im, layer_rgba, radius):
    g = layer_rgba.filter(ImageFilter.GaussianBlur(radius))
    out = Image.alpha_composite(im.convert("RGBA"), g)
    return Image.alpha_composite(out, layer_rgba).convert("RGB")


def led(im, pitch=4, dark=0.82):
    """Сетка светодиодов: тонкие тёмные линии через pitch пикселей (лента / экран вблизи)."""
    w, h = im.size
    m = Image.new("L", (w, h), 255)
    d = ImageDraw.Draw(m)
    v = int(255 * dark)
    for x in range(0, w, pitch):
        d.line([(x, 0), (x, h)], fill=v)
    for y in range(0, h, pitch):
        d.line([(0, y), (w, y)], fill=v)
    return ImageChops.multiply(im, Image.merge("RGB", (m, m, m)))


def grain(im, amount=14):
    """Зерно: шум со средним 128 → a + n − 128."""
    n = Image.effect_noise(im.size, amount).convert("RGB")
    return ImageChops.add(im, n, 1.0, -128)


def bars(im, col, top=True, bottom=True, t=4):
    d = ImageDraw.Draw(im)
    w, h = im.size
    if top:
        d.rectangle([0, 0, w, t], fill=col)
    if bottom:
        d.rectangle([0, h - t - 1, w, h], fill=col)


# ----------------------------------------------------------------------------------------------------------------------
# щиты 16:9
# ----------------------------------------------------------------------------------------------------------------------
def board_fight_night():
    im = ImageOps.fit(src(os.path.join(STEAM, "keyart_wide.jpg")), BOARD, Image.LANCZOS, centering=(0.66, 0.5))
    im = ImageEnhance.Contrast(im).enhance(1.08)
    im = side_shade(im, 0.62, 235)
    im = stripes(im, AMBER, 34, 70, 14, x0=0, x1=420)
    glow_text(im, (54, 150), "NULL", font(170), WHITE, glow=CYAN, radius=14)
    glow_text(im, (54, 330), "LEAGUE", font(96), CREAM, glow=None)
    ImageDraw.Draw(im).rectangle([56, 456, 420, 462], fill=AMBER)
    glow_text(im, (54, 476), "FIGHT NIGHT", font(64), AMBER, glow=ORANGE, radius=8)
    bars(im, CYAN, t=3)
    return im


def ball_joint(im, c, r):
    """Хромированный шарнир: шар в чашке, янтарное кольцо, голубой контровой свет."""
    w, h = im.size
    cx, cy = c
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    # шток вниз и чашка
    d.rectangle([cx - r * 0.22, cy + r * 0.6, cx + r * 0.22, h + 10], fill=(40, 46, 60, 255))
    d.rectangle([cx - r * 0.22, cy + r * 0.6, cx - r * 0.1, h + 10], fill=(90, 100, 120, 255))
    d.pieslice([cx - r * 1.12, cy - r * 0.2, cx + r * 1.12, cy + r * 1.25], 0, 180, fill=(28, 32, 44, 255))
    im.paste(Image.alpha_composite(im.convert("RGBA"), lay).convert("RGB"))
    # шар: радиальный градиент от блика
    sphere = radial((w, h), (cx - r * 0.35, cy - r * 0.4), r * 1.55, (250, 250, 255), (22, 26, 38))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    im.paste(sphere, (0, 0), m)
    # отражение горизонта (тёмная полоса) и блик
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.chord([cx - r, cy - r * 0.05, cx + r, cy + r], 0, 180, fill=(10, 14, 26, 120))
    d.ellipse([cx - r * 0.55, cy - r * 0.7, cx - r * 0.15, cy - r * 0.42], fill=(255, 255, 255, 190))
    lay = lay.filter(ImageFilter.GaussianBlur(r * 0.04))
    lm = Image.new("L", (w, h), 0)
    ImageDraw.Draw(lm).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    lay.putalpha(ImageChops.multiply(lay.getchannel("A"), lm))
    out = Image.alpha_composite(im.convert("RGBA"), lay)
    # янтарное кольцо-экватор и голубой контур
    ring = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ring)
    d.arc([cx - r * 1.02, cy - r * 0.32, cx + r * 1.02, cy + r * 0.32], 0, 180, fill=AMBER + (255,), width=int(r * 0.09))
    d.arc([cx - r, cy - r, cx + r, cy + r], -70, 40, fill=CYAN + (255,), width=int(r * 0.035))
    out = Image.alpha_composite(out, ring.filter(ImageFilter.GaussianBlur(r * 0.08)))
    out = Image.alpha_composite(out, ring)
    im.paste(out.convert("RGB"))


def board_joints():
    im = radial(BOARD, (760, 290), 520, (26, 44, 92), DEEP)
    im = stripes(im, CYAN, 16, 90, 3, x0=0, x1=BOARD[0])
    ball_joint(im, (770, 270), 170)
    glow_text(im, (52, 118), "ORBIT", font(150), CREAM, glow=AMBER, radius=10)
    glow_text(im, (52, 278), "JOINTS", font(110), AMBER)
    ImageDraw.Draw(im).rectangle([56, 420, 440, 425], fill=CYAN)
    glow_text(im, (54, 440), "HOLDS IN ZERO-G", font(58), WHITE, glow=CYAN, radius=6)
    bars(im, AMBER, t=3)
    return im


def lightning(d, a, b, rnd, col, width, depth=5, jag=0.18):
    pts = [a, b]
    for _ in range(depth):
        out = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            L = math.hypot(q[0] - p[0], q[1] - p[1])
            nx, ny = -(q[1] - p[1]) / max(L, 1e-6), (q[0] - p[0]) / max(L, 1e-6)
            o = rnd.uniform(-jag, jag) * L
            out += [(mx + nx * o, my + ny * o), q]
        pts = out
    d.line(pts, fill=col, width=width, joint="curve")


def board_cores():
    im = vgrad(BOARD, (8, 14, 36), (16, 30, 70))
    im = stripes(im, AMBER, 46, 110, 26, slope=-0.6, x0=480, x1=BOARD[0])
    cx, cy, r = 760, 288, 170
    rnd = random.Random(11)
    hexo = [(cx + r * math.cos(math.pi / 6 + k * math.pi / 3), cy + r * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    hexi = [(cx + r * 0.72 * math.cos(math.pi / 6 + k * math.pi / 3), cy + r * 0.72 * math.sin(math.pi / 6 + k * math.pi / 3))
            for k in range(6)]
    d = ImageDraw.Draw(im)
    d.polygon(hexo, fill=(30, 34, 48), outline=(120, 130, 150), width=6)
    core = radial(BOARD, (cx, cy), r * 0.9, (230, 255, 255), (10, 110, 190))
    m = Image.new("L", BOARD, 0)
    ImageDraw.Draw(m).polygon(hexi, fill=255)
    im.paste(core, (0, 0), m)
    bolts = Image.new("RGBA", BOARD, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bolts)
    for k in range(7):
        a = rnd.uniform(0, math.tau)
        L = rnd.uniform(1.3, 2.0) * r
        lightning(bd, (cx + math.cos(a) * r * 0.5, cy + math.sin(a) * r * 0.5), (cx + math.cos(a) * L, cy + math.sin(a) * L), rnd,
                  (200, 245, 255, 255), 4)
    for k in range(6):   # болты-клеммы по углам шестигранника
        x, y = hexo[k]
        bd.ellipse([x - 12, y - 12, x + 12, y + 12], fill=AMBER + (255,))
    im = add_glow(im, bolts, 9)
    glow_text(im, (50, 112), "VOLTA", font(156), WHITE, glow=CYAN, radius=14)
    glow_text(im, (50, 278), "CORES", font(112), CYAN, glow=CYAN, radius=8)
    ImageDraw.Draw(im).rectangle([54, 424, 452, 430], fill=AMBER)
    glow_text(im, (52, 444), "MORE CHARGE PER HIT", font(52), AMBER, glow=ORANGE, radius=6)
    bars(im, CYAN, t=3)
    return im


def board_nulltv():
    im = vgrad(BOARD, (12, 22, 52), DEEP)
    im = stripes(im, AMBER, 22, 60, 8, x0=0, x1=440)
    poster = src(os.path.join(STEAM, "poster_live.jpg"))
    crop = poster.crop((40, 470, 1000, 1330))                # N0 и телевизор без верхней надписи
    crop = crop.resize((int(crop.width * BOARD[1] / crop.height), BOARD[1]), Image.LANCZOS)
    x0 = BOARD[0] - crop.width + 30
    m = Image.new("L", crop.size, 255)
    md = ImageDraw.Draw(m)
    for x in range(120):
        md.line([(x, 0), (x, crop.height)], fill=int(255 * x / 120))
    im.paste(crop, (x0, 0), m)
    glow_text(im, (50, 96), "NULL", font(168), WHITE, glow=CYAN, radius=14)
    glow_text(im, (54, 290), "TV", font(130), AMBER, glow=ORANGE, radius=10)
    d = ImageDraw.Draw(im)
    d.ellipse([214, 330, 252, 368], fill=RED)
    glow_text(im, (264, 324), "LIVE", font(46), WHITE)
    d.rectangle([54, 458, 430, 463], fill=CYAN)
    glow_text(im, (52, 478), "LIVE FROM THE DOME", font(50), CREAM)
    bars(im, AMBER, t=3)
    return im


def stencil(im, xy, text, f, fill, cut_col):
    """Трафарет: буквы с поперечными перемычками цвета фона."""
    b = glow_text(im, xy, text, f, fill)
    d = ImageDraw.Draw(im)
    hgt = b[3] - b[1]
    for k in (0.36, 0.7):
        y = b[1] + hgt * k
        d.rectangle([b[0], y, b[2], y + max(3, hgt * 0.035)], fill=cut_col)
    return b


def board_scrap_cup():
    ph = src(os.path.join(GARAGE, "photo_e.png")).crop((10, 10, 330, 250))   # кадр Свалки на закате (без рамки полароида)
    im = ImageOps.fit(ph, BOARD, Image.LANCZOS, centering=(0.6, 0.5)).filter(ImageFilter.UnsharpMask(3, 80, 2))
    im = ImageEnhance.Color(im).enhance(1.15)
    im = side_shade(im, 0.62, 205, col=(30, 14, 8))
    im = grain(im, 9)
    rnd = random.Random(5)
    sc = Image.new("RGBA", BOARD, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sc)
    for _ in range(90):   # царапины
        x, y = rnd.uniform(0, BOARD[0]), rnd.uniform(0, BOARD[1])
        a = rnd.uniform(-0.6, 0.6)
        L = rnd.uniform(10, 70)
        sd.line([(x, y), (x + L * math.cos(a), y + L * math.sin(a))], fill=(230, 210, 180, rnd.randint(40, 110)), width=1)
    for _ in range(26):   # ржавые потёки
        x = rnd.uniform(0, BOARD[0])
        y = rnd.uniform(0, BOARD[1] * 0.6)
        sd.rectangle([x, y, x + rnd.uniform(2, 6), y + rnd.uniform(40, 160)], fill=(120, 50, 18, rnd.randint(50, 110)))
    im = Image.alpha_composite(im.convert("RGBA"), sc.filter(ImageFilter.GaussianBlur(0.6))).convert("RGB")
    stencil(im, (48, 98), "SCRAP", font(162), CREAM, (40, 18, 10))
    stencil(im, (48, 270), "CUP", font(150), ORANGE, (40, 18, 10))
    glow_text(im, (52, 470), "BUILT FROM JUNK", font(56), CREAM)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, BOARD[0] - 1, BOARD[1] - 1], outline=(70, 30, 12), width=12)
    for x in (22, BOARD[0] - 22):   # заклёпки
        for y in (22, BOARD[1] // 2, BOARD[1] - 22):
            d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(150, 120, 90), outline=(50, 30, 20), width=2)
    return im


# ----------------------------------------------------------------------------------------------------------------------
# LED-ленты бортов (≈9:1), изогнутый баннер, флаг
# ----------------------------------------------------------------------------------------------------------------------
def ribbon(items, bg0, bg1, stripe_col, line_col, emblem=False):
    """Лента из блоков текста по ширине; emblem — эмблема Лиги в середине."""
    w, h = RIBBON
    im = vgrad(RIBBON, bg0, bg1)
    im = stripes(im, stripe_col, 40, 46, 10, x0=0, x1=170)
    im = stripes(im, stripe_col, 40, 46, 10, x0=w - 170, x1=w)
    cx_list = [w * (i + 0.5) / len(items) for i in range(len(items))]
    for (text, col, px), cx in zip(items, cx_list):
        if text == "@EMBLEM":
            e = src(os.path.join(STEAM, "league_emblem.jpg")).resize((h - 16, h - 16), Image.LANCZOS)
            m = Image.new("L", e.size, 0)
            ImageDraw.Draw(m).ellipse([4, 4, e.width - 4, e.height - 4], fill=255)
            im.paste(e, (int(cx - e.width / 2), 8), m)
        elif text == "@DOT":
            ImageDraw.Draw(im).ellipse([cx - 22, h / 2 - 22, cx + 22, h / 2 + 22], fill=RED)
        else:
            glow_text(im, (cx, h / 2 + 4), text, fit_font(text, px, w / len(items) * 0.86), col, glow=col, radius=8, anchor="mm")
    bars(im, line_col, t=4)
    return led(im, 4, 0.8)


def ribbon_league():
    return ribbon([("NULL LEAGUE", WHITE, 128), ("@EMBLEM", None, 0), ("SEASON ZERO", AMBER, 120)], (10, 20, 48), DEEP, AMBER, CYAN)


def ribbon_joints():
    return ribbon([("ORBIT JOINTS", CREAM, 128), ("HOLDS IN ZERO-G", AMBER, 104)], (16, 22, 40), (6, 8, 16), AMBER, AMBER)


def ribbon_cores():
    return ribbon([("VOLTA CORES", CYAN, 130), ("MORE CHARGE PER HIT", WHITE, 96)], (6, 22, 44), (4, 8, 18), CYAN, CYAN)


def ribbon_nulltv():
    return ribbon([("NULL TV", WHITE, 134), ("@DOT", None, 0), ("LIVE FROM THE DOME", AMBER, 100)], (24, 12, 30), (8, 6, 14),
                  ORANGE, ORANGE)


def banner_curved():
    w, h = CURVED
    im = ImageOps.fit(src(os.path.join(STEAM, "keyart_wide.jpg")), CURVED, Image.LANCZOS, centering=(0.55, 0.42))
    im = side_shade(im, 0.4, 230)
    im = side_shade(im, 0.4, 230, side="right")
    glow_text(im, (60, h / 2 + 6), "NULL LEAGUE", fit_font("NULL LEAGUE", 170, w * 0.33), WHITE, glow=CYAN, radius=14, anchor="lm")
    glow_text(im, (w - 60, h / 2 + 6), "SEASON ZERO", fit_font("SEASON ZERO", 160, w * 0.3), AMBER, glow=ORANGE, radius=12, anchor="rm")
    bars(im, AMBER, t=6)
    return im


def flag_null():
    w, h = FLAG
    im = ImageOps.fit(src(os.path.join(STEAM, "capsule_tall.jpg")), FLAG, Image.LANCZOS, centering=(0.5, 0.45))
    g = Image.new("L", FLAG, 0)
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / h
        a = max(0.0, 1.0 - t / 0.32) + max(0.0, (t - 0.78) / 0.22)
        d.line([(0, y), (w, y)], fill=int(235 * min(1.0, a)))
    im = Image.composite(Image.new("RGB", FLAG, DEEP), im, g)
    glow_text(im, (w / 2, 150), "NULL", font(230), AMBER, glow=ORANGE, radius=14, anchor="mm")
    glow_text(im, (w / 2, h - 110), "ZERO-G", font(118), CREAM, glow=CYAN, radius=10, anchor="mm")
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], outline=AMBER, width=10)
    return im


BUILDERS = {
    "board_fight_night": board_fight_night, "board_joints": board_joints, "board_cores": board_cores,
    "board_nulltv": board_nulltv, "board_scrap_cup": board_scrap_cup,
    "ribbon_league": ribbon_league, "ribbon_joints": ribbon_joints, "ribbon_cores": ribbon_cores, "ribbon_nulltv": ribbon_nulltv,
    "banner_curved": banner_curved, "flag_null": flag_null,
}


def main():
    codex = sys.argv[sys.argv.index("--codex") + 1] if "--codex" in sys.argv else None
    os.makedirs(OUT, exist_ok=True)
    for name, fn in BUILDERS.items():
        how = "сборка"
        im = None
        if codex and name in CODEX:
            jid, size, cen = CODEX[name]
            p = os.path.join(codex, jid + ".png")
            if os.path.exists(p):
                im = ImageOps.fit(src(p), size, Image.LANCZOS, centering=cen)
                how = "codex " + jid
        if im is None:
            im = fn()
        dst = os.path.join(OUT, name + ".jpg")
        im.save(dst, quality=88, optimize=True)
        print("ok %-18s %-10s %s → %s" % (name, "%dx%d" % im.size, how, os.path.relpath(dst, GODOT)))
    if codex and os.path.exists(os.path.join(codex, "hero_wide.png")):
        dst = os.path.join(STEAM, "hero_wide.jpg")
        src(os.path.join(codex, "hero_wide.png")).save(dst, quality=92, optimize=True)
        print("ok hero_wide → docs/steam/hero_wide.jpg (steam_capsules.py возьмёт его для library_hero)")


if __name__ == "__main__":
    main()
