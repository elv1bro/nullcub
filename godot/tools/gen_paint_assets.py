#!/usr/bin/env python3
"""Контент покраски куклы (docs/plan-demo/BODY_PAINT.md §1, §3, §6): трафареты, звук баллончика, картинка-фикстура.
Всё рисуется и синтезируется здесь же — ни одного внешнего сэмпла или картинки, поэтому вопросов лицензий нет. Исключение —
цифры: это растр глифов системного шрифта (растровые картинки текста лицензии шрифтов macOS допускают; нужно совсем без
чужого — уберите шрифты из FONT_CANDIDATES, будут свои семисегментные). Запуск из корня репозитория (нужны Pillow; для звука ещё numpy):

    python3 godot/tools/gen_paint_assets.py                    # всё
    python3 godot/tools/gen_paint_assets.py --only stencils    # stencils | audio | fixture, через запятую
    python3 godot/tools/gen_paint_assets.py --sheet /tmp/s.png # плюс обзорный лист трафаретов (в проект не класть)

затем godot --headless --path godot --import. Скрипт детерминирован (фиксированные сиды): повторный запуск даёт те же байты,
id фикстуры в KitImages не «плывёт».

ТРАФАРЕТЫ → godot/assets/textures/paint_stencils/<имя>.png
  256×256 RGBA: RGB везде белый (и под прозрачным — без тёмной каймы при фильтрации), фигура — в альфе. Рисуются в 1024²
  (ImageDraw, суперсэмплинг ×4), острые углы чуть скругляются (размытие + порог), затем бокс-уменьшение до 256² — ровный
  сглаженный край. Поле ≈ 6 % по краю, чтобы декаль не резала фигуру. Жирные формы и прорези ≥ 7 пикс. — читаются на кукле
  с 5 см. Порядок (он же порядок сетки в мастерской) — STENCILS ниже:
    star crown skull lightning heart arrow crossbones gear target flame digit_0 … digit_9
  crown — корона Башни как на баннерах арены и в заставке (assets/textures/decals/crown.png, comic_title.gd): три зубца,
  средний выше, шары на концах, ромб-прорезь, отдельный обод с тремя дырками. crossbones — две скрещённые кости без черепа
  (череп — свой трафарет, их можно наложить друг на друга). arrow смотрит вправо (Q/E крутят). Цифры — Arial Black (запасные:
  Impact, DejaVu Sans Bold, иначе рисованные семисегментные), общий кегль, каждая по центру своих чернил.

ЗВУК → godot/assets/audio/paint/*.wav — 44.1 кГц, моно, 16 бит, пик −6 dBFS:
  spray_loop.wav  — шипение баллончика «пссшш», петля ровно 1.000 с (44100 сэмплов). Шум собран прямо в спектре (обратное
      БПФ длиной ровно в петлю, у каждой гармоники целое число периодов), модуляции тоже целочисленные по частоте, брызги
      раскиданы по кругу — поэтому шов петли отсутствует математически, без кроссфейда. Спектр: широкий горб ≈ 4.4 кГц
      (свист струи), «ш» ≈ 2.5 кГц, слабая турбулентность ≈ 400 Гц, спад выше 10 кГц; лёгкая дрожь напора 6/11 Гц и редкие
      щелчки капель. В файле 44101 сэмпл: последний — копия первого (сторожевой), smpl-чанк — петля 0…44099. Рядом
      .import-заготовка (пишется, только если файла ещё нет): edit/loop_mode=2 (Forward), loop_end=-1, без сжатия и без trim —
      Godot ставит loop_end = frames − 1 = 44100, период ровно 1 с, звук импортируется сразу зацикленным.
  spray_start.wav — атака нажатия, 0.32 с: щелчок пластикового колпачка, «пф» клапана (шум темнеет→светлеет, пока растёт
      напор), затухает сам. Играть одновременно с запуском петли (петлю поднять за ~60 мс): start — слой атаки поверх неё.
  can_rattle.wav  — «клац-клац»: шарик-мешалка дважды бьёт в жестяную стенку. Модальный синтез: 8 неровных мод
      банки 0.6–9 кГц с разным затуханием, короткий шумовой удар, пара отскоков шарика, ранее отражение внутри банки.

ФИКСТУРА → godot/tests/fixtures/paint/sticker_fixture.png — 300×200 RGBA «испытательная таблица»: цветные полосы, серый
  клин, шахматка, надпись TEST, красная точка в левом верхнем углу (видно отражение/поворот), скруглённые прозрачные углы
  (проверка альфы у наклейки). Для paint_probe: KitImages.import_file → стабильный id."""
import argparse
import math
import os
import struct
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

try:
    import numpy as np
except ImportError:     # звук без numpy не собрать; трафареты и фикстура обходятся Pillow
    np = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # godot/
STENCIL_DIR = os.path.join(ROOT, "assets", "textures", "paint_stencils")
AUDIO_DIR = os.path.join(ROOT, "assets", "audio", "paint")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "paint", "sticker_fixture.png")

N = 256          # сторона трафарета
SS = 4           # суперсэмплинг
S = N * SS       # сторона холста

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/Library/Fonts/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/Impact.ttf",
    "/Library/Fonts/Impact.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
]


# ------------------------------------------------------------------------------------------------ трафареты: примитивы
def canvas():
    return Image.new("L", (S, S), 0)


def px(pts):
    return [(x * S, y * S) for x, y in pts]


def poly(d, pts, fill=255):
    d.polygon(px(pts), fill=fill)


def ellipse(d, cx, cy, rx, ry=None, fill=255):
    ry = rx if ry is None else ry
    d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=fill)


def rrect(d, x0, y0, x1, y1, r, fill=255):
    d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=fill)


def capsule(d, a, b, r, fill=255):
    """Толстая линия с круглыми концами: a, b — концы, r — полутолщина."""
    ax, ay = a
    bx, by = b
    l = math.hypot(bx - ax, by - ay) or 1e-9
    nx, ny = -(by - ay) / l * r, (bx - ax) / l * r
    poly(d, [(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill)
    ellipse(d, ax, ay, r, fill=fill)
    ellipse(d, bx, by, r, fill=fill)


def bezier(p0, p1, p2, p3, n=32):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def arc(cx, cy, r, a0, a1, n=48):
    """Дуга в градусах (y вниз: 90° — низ)."""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def soften(im, r):
    """Скругляет острые углы на r пикс. холста: размытие + порог (бинарная маска остаётся бинарной)."""
    if r <= 0:
        return im
    return im.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v >= 128 else 0)


def fit_to_box(pts, x0, y0, x1, y1):
    """Равномерно вписать контур в рамку (по центру)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    k = min((x1 - x0) / (max(xs) - min(xs)), (y1 - y0) / (max(ys) - min(ys)))
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    return [(mx + (x - cx) * k, my + (y - cy) * k) for x, y in pts]


# ------------------------------------------------------------------------------------------------ трафареты: фигуры
def st_star():
    im = canvas()
    d = ImageDraw.Draw(im)
    R, ri = 0.46, 0.46 * 0.48          # толстая звезда: внутренний радиус почти половина
    cy = 0.5 + R * (1 - math.cos(math.radians(36))) / 2   # оптический центр: верх и низ на равных полях
    pts = []
    for k in range(10):
        r = R if k % 2 == 0 else ri
        a = math.radians(-90 + 36 * k)
        pts.append((0.5 + r * math.cos(a), cy + r * math.sin(a)))
    poly(d, pts)
    return soften(im, 9)


def st_crown():
    """Корона Башни: как на баннерах арены (decals/crown.png) и в заставке — три зубца, средний выше, шары, ромб, обод."""
    im = canvas()
    d = ImageDraw.Draw(im)
    dy = 0.01
    body = [(0.14, 0.70), (0.14, 0.34), (0.33, 0.53), (0.50, 0.22), (0.67, 0.53), (0.86, 0.34), (0.86, 0.70)]
    poly(d, [(x, y + dy) for x, y in body])
    ellipse(d, 0.50, 0.155 + dy, 0.068)
    ellipse(d, 0.14, 0.295 + dy, 0.058)
    ellipse(d, 0.86, 0.295 + dy, 0.058)
    rrect(d, 0.10, 0.745 + dy, 0.90, 0.905 + dy, 0.02)
    im = soften(im, 6)
    d = ImageDraw.Draw(im)
    poly(d, [(0.50, 0.475 + dy), (0.568, 0.555 + dy), (0.50, 0.635 + dy), (0.432, 0.555 + dy)], fill=0)   # ромб
    for x in (0.29, 0.50, 0.71):
        ellipse(d, x, 0.825 + dy, 0.036, fill=0)                                                             # дырки обода
    return im


def st_skull():
    im = canvas()
    d = ImageDraw.Draw(im)
    ellipse(d, 0.50, 0.42, 0.37, 0.345)                       # свод
    rrect(d, 0.29, 0.58, 0.71, 0.91, 0.07)                    # челюсть
    im = soften(im, 8)
    d = ImageDraw.Draw(im)
    for sx in (-1, 1):                                        # глазницы: чуть скошены к носу — «злой» прищур
        pts = []
        for i in range(64):
            a = 2 * math.pi * i / 64
            x, y = 0.105 * math.cos(a), 0.092 * math.sin(a)
            if y < 0:                                         # верхняя кромка срезана наклонно
                y *= 1.0 - 0.35 * (0.5 + 0.5 * sx * -x / 0.105)
            pts.append((0.5 + sx * 0.145 + x, 0.475 + y))
        poly(d, pts, fill=0)
    poly(d, [(0.50, 0.585), (0.548, 0.675), (0.452, 0.675)], fill=0)   # нос
    for x in (0.405, 0.50, 0.595):                            # зубы: прорези до низа челюсти
        rrect(d, x - 0.017, 0.765, x + 0.017, 0.95, 0.012, fill=0)
    return im


def st_lightning():
    im = canvas()
    d = ImageDraw.Draw(im)
    pts = [(0.52, 0.05), (0.84, 0.05), (0.64, 0.37), (0.84, 0.37), (0.30, 0.96), (0.43, 0.56), (0.20, 0.56)]
    poly(d, fit_to_box(pts, 0.17, 0.06, 0.83, 0.94))
    return soften(im, 7)


def st_heart():
    im = canvas()
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(256):
        t = 2 * math.pi * i / 256
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((x * 1.06, y))                               # чуть шире классики — пухлее на маленькой детали
    poly(d, fit_to_box(pts, 0.06, 0.09, 0.94, 0.91))
    return soften(im, 6)


def st_arrow():
    im = canvas()
    d = ImageDraw.Draw(im)
    rrect(d, 0.07, 0.385, 0.56, 0.615, 0.03)                  # древко
    poly(d, [(0.47, 0.13), (0.94, 0.50), (0.47, 0.87)])      # наконечник
    return soften(im, 7)


def _bone(d, a, b, r_shaft, r_knob, fill=255):
    capsule(d, a, b, r_shaft, fill)
    ax, ay = a
    bx, by = b
    l = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / l, (by - ay) / l
    nx, ny = -uy, ux
    off = r_shaft * 0.95
    for (ex, ey), s in ((a, 1), (b, -1)):
        cx, cy = ex - ux * s * r_knob * 0.15, ey - uy * s * r_knob * 0.15
        ellipse(d, cx + nx * off, cy + ny * off, r_knob, fill=fill)
        ellipse(d, cx - nx * off, cy - ny * off, r_knob, fill=fill)


def st_crossbones():
    """Две скрещённые кости; верхняя обведена прорезью — видно, какая сверху."""
    im = canvas()
    d = ImageDraw.Draw(im)
    rs, rk, gap = 0.058, 0.078, 0.022
    a1, b1 = (0.225, 0.225), (0.775, 0.775)
    a2, b2 = (0.775, 0.225), (0.225, 0.775)
    _bone(d, a1, b1, rs, rk)
    _bone(d, a2, b2, rs + gap, rk + gap, fill=0)              # прорезь вокруг верхней кости
    _bone(d, a2, b2, rs, rk)
    return soften(im, 5)


def st_gear():
    im = canvas()
    d = ImageDraw.Draw(im)
    teeth, r_root, r_tip = 8, 0.325, 0.44
    step = 360 / teeth
    pts = []
    for k in range(teeth):
        a0 = -90 + k * step
        for a, r in ((a0 - 13.5, r_root), (a0 - 8.0, r_tip), (a0 + 8.0, r_tip), (a0 + 13.5, r_root)):
            pts.append((0.5 + r * math.cos(math.radians(a)), 0.5 + r * math.sin(math.radians(a))))
        pts += arc(0.5, 0.5, r_root, a0 + 13.5, a0 + step - 13.5, 12)[1:-1]
    poly(d, pts)
    im = soften(im, 7)
    d = ImageDraw.Draw(im)
    ellipse(d, 0.5, 0.5, 0.13, fill=0)                        # ось
    return im


def st_target():
    im = canvas()
    d = ImageDraw.Draw(im)
    ellipse(d, 0.5, 0.5, 0.44)
    ellipse(d, 0.5, 0.5, 0.32, fill=0)
    ellipse(d, 0.5, 0.5, 0.24)
    ellipse(d, 0.5, 0.5, 0.155, fill=0)
    ellipse(d, 0.5, 0.5, 0.08)
    return im


def _tongue(cx, cy, w, h, lean):
    """Язык пламени: круглое дно радиуса w/2 с центром (cx, cy), кончик на h выше, отклонён на lean."""
    r = w / 2
    tip = (cx + lean, cy - h)
    right = bezier((cx + r, cy), (cx + r * 1.02, cy - h * 0.42), (cx + lean * 0.55 + r * 0.30, cy - h * 0.78), tip)
    left = bezier(tip, (cx + lean * 0.55 - r * 0.45, cy - h * 0.70), (cx - r * 1.02, cy - h * 0.36), (cx - r, cy))
    bottom = arc(cx, cy, r, 180, 0, 40)[1:-1]                 # от левого края через низ (90°, y вниз) к правому
    return right + left[1:] + bottom


def st_flame():
    """Пламя: главный язык чуть влево, язычки по бокам, сердцевина-капля."""
    im = canvas()
    d = ImageDraw.Draw(im)
    b = (0.50, 0.935)
    segs = [
        ((0.69, 0.935), (0.815, 0.80), (0.815, 0.635)),     # правый бок
        ((0.815, 0.50), (0.80, 0.38), (0.745, 0.285)),       # правый язычок
        ((0.715, 0.37), (0.675, 0.43), (0.635, 0.465)),      # впадина справа
        ((0.655, 0.30), (0.60, 0.15), (0.475, 0.05)),        # главный язык, правая кромка
        ((0.45, 0.18), (0.36, 0.28), (0.365, 0.415)),        # главный язык, левая кромка
        ((0.32, 0.36), (0.25, 0.30), (0.215, 0.185)),        # левый язычок
        ((0.175, 0.33), (0.185, 0.50), (0.185, 0.64)),       # левый бок
        ((0.185, 0.82), (0.32, 0.935), b),                   # дно
    ]
    pts = [b]
    for c1, c2, e in segs:
        pts += bezier(pts[-1], c1, c2, e)[1:]
    poly(d, pts)
    im = soften(im, 7)
    d = ImageDraw.Draw(im)
    poly(d, _tongue(0.50, 0.755, 0.25, 0.32, -0.035), fill=0)   # сердцевина
    return im


# ------------------------------------------------------------------------------------------------ цифры
def _font_path():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    return ""


SEG = {  # семисегментные цифры на случай, если шрифта нет: a b c d e f g
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc",
    "8": "abcdefg", "9": "abcdfg",
}


def _digit_segments(ch):
    im = canvas()
    d = ImageDraw.Draw(im)
    x0, x1, y0, y1, ym, r = 0.28, 0.72, 0.13, 0.87, 0.50, 0.06
    seg = {"a": ((x0, y0), (x1, y0)), "b": ((x1, y0), (x1, ym)), "c": ((x1, ym), (x1, y1)), "d": ((x0, y1), (x1, y1)),
           "e": ((x0, ym), (x0, y1)), "f": ((x0, y0), (x0, ym)), "g": ((x0, ym), (x1, ym))}
    for s in SEG[ch]:
        capsule(d, seg[s][0], seg[s][1], r)
    return im


def _center_ink(src):
    """Холст S² с чернилами src ровно по центру."""
    ink = src.crop(src.getbbox())
    im = canvas()
    im.paste(ink, ((S - ink.width) // 2, (S - ink.height) // 2))
    return im


def st_digits():
    """{"digit_0": маска, …}: общий кегль (по самой крупной цифре), каждая по центру своей чернильной рамки."""
    path = _font_path()
    out = {}
    if not path:
        print("  ! шрифт не найден — цифры семисегментные", file=sys.stderr)
        for ch in "0123456789":
            out["digit_" + ch] = _center_ink(_digit_segments(ch))
        return out, "7-seg"
    box_w, box_h = 0.80 * S, 0.84 * S
    probe = ImageFont.truetype(path, 400)
    bw = max(probe.getbbox(ch)[2] - probe.getbbox(ch)[0] for ch in "0123456789")
    bh = max(probe.getbbox(ch)[3] - probe.getbbox(ch)[1] for ch in "0123456789")
    size = int(400 * min(box_w / bw, box_h / bh))
    font = ImageFont.truetype(path, size)
    for ch in "0123456789":
        tmp = Image.new("L", (S * 2, S * 2), 0)
        ImageDraw.Draw(tmp).text((S // 2, S // 2), ch, font=font, fill=255)
        out["digit_" + ch] = _center_ink(tmp)                  # по чернилам: у «1» в шрифте поля несимметричны
    return out, os.path.basename(path)


SHAPES = [("star", st_star), ("crown", st_crown), ("skull", st_skull), ("lightning", st_lightning), ("heart", st_heart),
          ("arrow", st_arrow), ("crossbones", st_crossbones), ("gear", st_gear), ("target", st_target), ("flame", st_flame)]
STENCILS = [n for n, _ in SHAPES] + ["digit_%d" % i for i in range(10)]


def finish(mask_ss):
    """Холст 1024² → RGBA 256²: белый RGB, альфа = бокс-уменьшенная маска."""
    a = mask_ss.filter(ImageFilter.GaussianBlur(0.9)).reduce(SS)   # чуть мягче 17 ступеней бинарной маски
    white = Image.new("L", (N, N), 255)
    return Image.merge("RGBA", (white, white, white, a))


def make_stencils():
    os.makedirs(STENCIL_DIR, exist_ok=True)
    masks = {}
    for name, fn in SHAPES:
        masks[name] = fn()
    digits, font = st_digits()
    masks.update(digits)
    out = {}
    for name in STENCILS:
        im = finish(masks[name])
        bbox = im.getchannel("A").getbbox()
        im.save(os.path.join(STENCIL_DIR, name + ".png"), optimize=True)
        cover = im.getchannel("A").resize((1, 1), Image.BOX).getpixel((0, 0)) / 255.0
        print(f"  {name + '.png':16s} ink {bbox}  cover {cover:.2f}")
        out[name] = im
    print(f"трафареты: {len(STENCILS)} → {os.path.relpath(STENCIL_DIR)}  (цифры: {font})")
    return out


def contact_sheet(stencils, path):
    """Обзор: крупно на тёмном, затем все в 48 и 28 пикс. на дереве — примерно так трафарет в 5 см виден с камеры стенда."""
    cols, cell, lab = 5, 272, 22
    rows = math.ceil(len(STENCILS) / cols)
    small = [48, 28]
    h = rows * (cell + lab) + 24 + sum(s + 16 for s in small)
    sheet = Image.new("RGB", (cols * cell, h), (38, 40, 46))
    d = ImageDraw.Draw(sheet)
    palette = [(235, 64, 52), (250, 196, 45), (80, 200, 120), (70, 150, 250), (240, 240, 240)]
    for i, name in enumerate(STENCILS):
        x, y = (i % cols) * cell, (i // cols) * (cell + lab)
        d.rectangle([x + 4, y + 4, x + cell - 5, y + cell - 5], outline=(70, 72, 80))
        col = Image.new("RGB", (N, N), palette[i % len(palette)])
        sheet.paste(col, (x + 8, y + 8), stencils[name].getchannel("A"))
        d.text((x + 10, y + cell + 2), name, fill=(220, 220, 220))
    y = rows * (cell + lab) + 12
    wood = (150, 104, 62)
    for s in small:
        d.rectangle([0, y - 4, cols * cell, y + s + 4], fill=wood)
        for i, name in enumerate(STENCILS):
            a = stencils[name].getchannel("A").resize((s, s), Image.LANCZOS)
            col = Image.new("RGB", (s, s), palette[i % len(palette)] if i % len(palette) != 4 else (30, 30, 30))
            sheet.paste(col, (8 + i * (s + 16), y), a)
        y += s + 16
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)
    print(f"обзорный лист → {path}")


# ------------------------------------------------------------------------------------------------ фикстура
def make_fixture():
    w, h = 300, 200
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bars = [(192, 192, 192), (230, 215, 0), (0, 200, 220), (0, 190, 60), (220, 0, 200), (225, 20, 20), (20, 40, 225)]
    bw = w / len(bars)
    for i, c in enumerate(bars):
        d.rectangle([round(i * bw), 0, round((i + 1) * bw) - 1, 129], fill=c + (255,))
    for x in range(150):                                       # серый клин
        v = round(x / 149 * 255)
        d.line([(x, 130), (x, 199)], fill=(v, v, v, 255))
    for yy in range(130, 200, 10):                             # шахматка
        for xx in range(150, 300, 10):
            c = 20 if ((xx // 10) + (yy // 10)) % 2 == 0 else 235
            d.rectangle([xx, yy, xx + 9, yy + 9], fill=(c, c, c, 255))
    d.ellipse([12, 12, 32, 32], fill=(255, 0, 0, 255), outline=(0, 0, 0, 255), width=2)   # метка «верх-лево»
    path = _font_path()
    try:
        font = ImageFont.truetype(path, 64) if path else ImageFont.load_default(64)
    except TypeError:                                          # Pillow < 10.1: шрифт по умолчанию без размера
        font = ImageFont.load_default()
    l, t, r, b = d.textbbox((0, 0), "TEST", font=font, stroke_width=5)
    d.text(((w - (r - l)) / 2 - l, (h - (b - t)) / 2 - t - 12), "TEST", font=font, fill=(255, 255, 255, 255),
           stroke_width=5, stroke_fill=(0, 0, 0, 255))
    # скруглённые прозрачные углы (4× маска для гладкого края)
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=22 * 4, fill=255)
    im.putalpha(ImageChops.darker(im.getchannel("A"), m.reduce(4)))
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    im.save(FIXTURE, optimize=True)
    print(f"фикстура: {os.path.relpath(FIXTURE)} {im.size} {im.mode}")


# ------------------------------------------------------------------------------------------------ звук
SR = 44100
PEAK = 10 ** (-6 / 20)      # −6 dBFS
LOOP_IMPORT_STUB = """[remap]

importer="wav"
type="AudioStreamWAV"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=2
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""


def write_wav(path, x, loop_frames=0):
    """PCM 16 бит моно; loop_frames > 0 — smpl-чанк: петля 0…loop_frames − 1 (конец включительно, по спецификации RIFF)."""
    data = (np.clip(x, -1, 1) * 32767).round().astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data + (b"\0" if len(data) % 2 else b"")
    if loop_frames:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, loop_frames - 1, 0, 0)   # cue id, тип 0 (вперёд), начало, конец, дробь, раз
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def lognorm(f, fc, octaves):
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / octaves) ** 2)


def hiss_shape(f, bright=1.0):
    """Амплитудный спектр шипения: струя ≈ 4.4 кГц, «ш» ≈ 2.5 кГц, турбулентность ≈ 400 Гц, спад выше ≈ 10 кГц;
    bright < 1 — темнее (начало нажатия, пока напор не набран)."""
    f = np.maximum(f, 1.0)
    m = lognorm(f, 4400 * bright, 0.95) + 0.65 * lognorm(f, 2500 * bright, 0.5) + 0.07 * lognorm(f, 420, 1.0)
    return m / (1 + (40.0 / f) ** 4) / np.sqrt(1 + (f / (10000 * bright)) ** 6)


def spectral_noise(n, shape_fn, rng):
    """Шум заданного спектра, периодичный на n сэмплах (обратное БПФ со случайными фазами)."""
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = shape_fn(f) * np.exp(2j * np.pi * rng.random(len(f)))
    spec[0] = 0
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


def periodic_lfo(n, lo, hi, rng):
    """Медленная случайная кривая из целых гармоник lo…hi Гц (петля 1 с → целое число периодов), σ = 1."""
    spec = np.zeros(n // 2 + 1, complex)
    k = np.arange(len(spec)) * SR / n
    sel = (k >= lo) & (k <= hi)
    spec[sel] = np.exp(2j * np.pi * rng.random(sel.sum()))
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


def soft_limit(x, knee=2.8):
    """x в единицах σ; мягко срезает редкие пики, чтобы при пике −6 dBFS шипение было достаточно громким."""
    return np.tanh(x / knee) * knee


def droplets(n, count, level, rng, wrap=True):
    """Редкие щелчки капель: 1–3 мс тона 2.5–6 кГц под окном Ханна, по кругу (wrap) — петля остаётся без шва."""
    y = np.zeros(n)
    for _ in range(count):
        ln = int(SR * rng.uniform(0.001, 0.003))
        tt = np.arange(ln) / SR
        burst = np.sin(2 * np.pi * rng.uniform(2500, 6000) * tt + rng.random() * 6.28) * np.hanning(ln)
        burst *= level * rng.uniform(0.4, 1.0)
        start = int(rng.integers(0, n))
        idx = (start + np.arange(ln)) % n if wrap else np.clip(start + np.arange(ln), 0, n - 1)
        y[idx] += burst
    return y


def spray_body(n, rng):
    """Шипение петли в единицах σ (до нормировки)."""
    t = np.arange(n) / SR
    hiss = spectral_noise(n, hiss_shape, rng)
    am = (1 + 0.055 * np.sin(2 * np.pi * 6 * t + rng.random() * 6.28) + 0.035 * np.sin(2 * np.pi * 11 * t + rng.random() * 6.28)
          + 0.03 * periodic_lfo(n, 15, 40, rng))
    return hiss * am + droplets(n, 26, 1.2, rng)


def make_audio():
    if np is None:
        print("звук пропущен: нет numpy (pip install numpy)", file=sys.stderr)
        return False
    os.makedirs(AUDIO_DIR, exist_ok=True)
    rng = np.random.default_rng(29092026)

    # --- spray_loop: ровно 1 с, шов отсутствует по построению
    n = SR
    loop = soft_limit(spray_body(n, rng))
    gain = PEAK / np.max(np.abs(loop))
    loop *= gain
    p = os.path.join(AUDIO_DIR, "spray_loop.wav")
    # сторожевой сэмпл = первому: импорт с loop_end=-1 даёт loop_end = frames − 1 = n (конец не включительно) — период ровно
    # n сэмплов, и кубическая интерполяция на стыке читает правильного соседа
    write_wav(p, np.append(loop, loop[0]), loop_frames=n)
    stub = p + ".import"
    if not os.path.exists(stub):
        with open(stub, "w") as f:
            f.write(LOOP_IMPORT_STUB)
    rms = 20 * math.log10(np.sqrt(np.mean(loop ** 2)))
    seam = abs(loop[0] - loop[-1]) / np.mean(np.abs(np.diff(loop)))
    print(f"  spray_loop.wav   {n / SR:.3f} s  peak {20 * math.log10(np.max(np.abs(loop))):.1f} dBFS  rms {rms:.1f} dBFS"
          f"  шов/средний шаг {seam:.2f}")

    # --- spray_start: щелчок колпачка + «пф» клапана, темнеет→светлеет, сам затухает
    ln = int(0.32 * SR)
    t = np.arange(ln) / SR
    white = rng.standard_normal(ln)
    f = np.fft.rfftfreq(ln, 1 / SR)
    wspec = np.fft.rfft(white)
    dark = np.fft.irfft(wspec * hiss_shape(f, 0.42), ln)
    bright = np.fft.irfft(wspec * hiss_shape(f, 1.12), ln)
    dark /= np.std(dark)
    bright /= np.std(bright)
    k = np.clip((t - 0.008) / 0.075, 0, 1)
    k = k * k * (3 - 2 * k)
    hiss = dark * (1 - k) + bright * k
    t0 = np.maximum(t - 0.010, 0)
    env = np.where(t < 0.010, 0.0, np.clip(t0 / 0.004, 0, 1)) * (0.55 + 1.0 * np.exp(-t0 / 0.035)) * np.exp(-t0 / 0.16)
    click = np.zeros(ln)
    for fr, dc, a in ((1850, 0.006, 1.0), (3350, 0.004, 0.7), (5200, 0.0025, 0.5), (820, 0.008, 0.35)):
        click += a * np.sin(2 * np.pi * fr * t + rng.random() * 6.28) * np.exp(-t / dc)
    click += np.diff(rng.standard_normal(ln), prepend=0.0) * np.exp(-t / 0.0012) * 0.8
    start = soft_limit(hiss * env + click * 1.1)            # щелчок не выше «пф», иначе нормировка утопит шипение
    start[: int(0.0005 * SR)] *= np.linspace(0, 1, int(0.0005 * SR))
    start[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR)) ** 2
    start *= gain
    if np.max(np.abs(start)) > PEAK:
        start *= PEAK / np.max(np.abs(start))
    write_wav(os.path.join(AUDIO_DIR, "spray_start.wav"), start)
    print(f"  spray_start.wav  {ln / SR:.3f} s  peak {20 * math.log10(np.max(np.abs(start))):.1f} dBFS")

    # --- can_rattle: «клац-клац» шарика в жестянке
    ln = int(0.46 * SR)
    t = np.arange(ln) / SR
    modes = [(1420, 0.050, 0.55), (2230, 0.042, 1.0), (3170, 0.032, 0.8), (4060, 0.027, 0.7), (5330, 0.020, 0.5),
             (6870, 0.015, 0.36), (8790, 0.010, 0.25), (640, 0.030, 0.28)]

    def clack(at, amp, detune, rng):
        y = np.zeros(ln)
        i0 = int(at * SR)
        tt = t[: ln - i0]
        hit = np.zeros(len(tt))
        for fr, dc, a in modes:
            a *= rng.uniform(0.75, 1.15)
            hit += a * np.sin(2 * np.pi * fr * detune * tt + rng.random() * 6.28) * np.exp(-tt / (dc * rng.uniform(0.85, 1.1)))
        hit += np.diff(rng.standard_normal(len(tt)), prepend=0.0) * np.exp(-tt / 0.0015) * 1.4
        hit[: int(0.0003 * SR)] *= np.linspace(0, 1, int(0.0003 * SR))
        y[i0:] += hit * amp
        return y

    rattle = np.zeros(ln)
    for at, amp, det in ((0.012, 1.0, 1.0), (0.188, 0.88, 0.972)):
        rattle += clack(at, amp, det, rng)
        for dt, a in ((0.011, 0.26), (0.024, 0.14), (0.034, 0.07)):          # отскоки шарика
            rattle += clack(at + dt * rng.uniform(0.85, 1.15), amp * a, det * rng.uniform(0.98, 1.03), rng)
    d = int(0.0013 * SR)                                                       # отражение внутри банки
    rattle[d:] += rattle[:-d] * 0.28
    rattle[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR)) ** 2
    rattle *= PEAK / np.max(np.abs(rattle))
    write_wav(os.path.join(AUDIO_DIR, "can_rattle.wav"), rattle)
    print(f"  can_rattle.wav   {ln / SR:.3f} s  peak {20 * math.log10(np.max(np.abs(rattle))):.1f} dBFS")
    print(f"звук → {os.path.relpath(AUDIO_DIR)}")
    return True


# ------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", default="stencils,audio,fixture")
    ap.add_argument("--sheet", default="", help="путь обзорного листа трафаретов (вне проекта)")
    args = ap.parse_args()
    parts = set(s.strip() for s in args.only.split(","))
    ok = True
    if "stencils" in parts or args.sheet:
        st = make_stencils()
        if args.sheet:
            contact_sheet(st, args.sheet)
    if "audio" in parts:
        ok = make_audio() and ok
    if "fixture" in parts:
        make_fixture()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
