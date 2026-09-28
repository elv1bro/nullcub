#!/usr/bin/env python3
"""Генератор UI-текстур HUD (R20: чернильные брызги под KO!, золотая корона, деревянная планка кнопок).

Запуск: python3 godot/assets/ui/gen_ui_textures.py  (нужен только Pillow)
Пишет рядом с собой: splatter.png (1024², чёрные брызги с альфой), crown.png (256², золотая корона с обводкой),
plank.png (512×128, нейтральная деревянная планка; цвет кнопки задаётся modulate в StyleBoxTexture),
brush_band.png (1024×192, горизонтальный мазок кисти с рваными краями — подложка заголовков).
Рисуется в 4× и уменьшается LANCZOS ради сглаживания. Seed фиксирован — результат воспроизводим.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))
SS = 4  # суперсэмплинг


def save(img: Image.Image, name: str, size: tuple[int, int]) -> None:
    img = img.resize(size, Image.LANCZOS)
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", path, img.size)


def splatter() -> None:
    rnd = random.Random(20)
    n = 1024 * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = n / 2
    r0 = n * 0.19
    black = (0, 0, 0, 255)
    # центральная клякса: неровный контур из 240 точек
    pts = []
    bumps = [(rnd.uniform(0, math.tau), rnd.uniform(0.02, 0.07), rnd.randint(2, 7)) for _ in range(6)]
    for i in range(240):
        a = math.tau * i / 240
        r = r0
        for ph, amp, k in bumps:
            r += r0 * amp * math.sin(k * a + ph)
        pts.append((cx + r * math.cos(a), cy + r * 0.78 * math.sin(a)))
    d.polygon(pts, fill=black)
    # крупные наплывы по краю ядра — контур становится «комковато-круглым», как у кляксы
    for _ in range(14):
        a = rnd.uniform(0, math.tau)
        dist = r0 * rnd.uniform(0.85, 1.15)
        rr = r0 * rnd.uniform(0.14, 0.3)
        x = cx + dist * math.cos(a)
        y = cy + dist * 0.8 * math.sin(a)
        d.ellipse([x - rr, y - rr * 0.9, x + rr, y + rr * 0.9], fill=black)
    # шипы-подтёки от центра
    for _ in range(16):
        a = rnd.uniform(0, math.tau)
        ln = r0 * rnd.uniform(1.25, 2.1)
        w = r0 * rnd.uniform(0.09, 0.2)
        tip = (cx + ln * math.cos(a), cy + ln * 0.8 * math.sin(a))
        base = (cx + r0 * 0.6 * math.cos(a), cy + r0 * 0.5 * math.sin(a))
        nx, ny = -math.sin(a) * w, math.cos(a) * w
        d.polygon([(base[0] + nx, base[1] + ny), (base[0] - nx, base[1] - ny), tip], fill=black)
        d.ellipse([tip[0] - w * 0.9, tip[1] - w * 0.9, tip[0] + w * 0.9, tip[1] + w * 0.9], fill=black)
    # капли
    for _ in range(260):
        a = rnd.uniform(0, math.tau)
        dist = r0 * rnd.uniform(1.05, 2.6)
        rr = r0 * rnd.uniform(0.015, 0.11) * (1.7 - dist / (r0 * 2.6))
        x = cx + dist * math.cos(a)
        y = cy + dist * 0.82 * math.sin(a)
        stretch = rnd.uniform(1.0, 2.6)
        drop = Image.new("L", (int(rr * 2 * stretch) + 4, int(rr * 2) + 4), 0)
        ImageDraw.Draw(drop).ellipse([2, 2, drop.width - 2, drop.height - 2], fill=255)
        drop = drop.rotate(-math.degrees(a), expand=True, resample=Image.BICUBIC)
        img.paste(black, (int(x - drop.width / 2), int(y - drop.height / 2)), drop)
    save(img, "splatter.png", (1024, 1024))


def crown() -> None:
    n = 256 * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    s = n / 256
    body = [
        (40, 196), (40, 88), (92, 146), (128, 52), (164, 146), (216, 88), (216, 196),
    ]
    body = [(x * s, y * s) for x, y in body]
    mask = Image.new("L", (n, n), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(body, fill=255)
    for x, y in [(40, 88), (128, 52), (216, 88)]:
        md.ellipse([(x - 16) * s, (y - 16) * s, (x + 16) * s, (y + 16) * s], fill=255)
    md.rounded_rectangle([34 * s, 178 * s, 222 * s, 212 * s], radius=6 * s, fill=255)
    # вертикальный градиент золота
    grad = Image.new("RGBA", (n, n))
    gd = ImageDraw.Draw(grad)
    for y in range(n):
        t = y / n
        r = int(255 - 40 * t)
        g = int(214 - 90 * t)
        b = int(64 - 30 * t)
        gd.line([(0, y), (n, y)], fill=(r, g, b, 255))
    gold = Image.composite(grad, img, mask)
    # тёмная обводка: расширенная маска под золотом
    outline = mask.filter(ImageFilter.MaxFilter(int(7 * s) | 1))
    dark = Image.new("RGBA", (n, n), (78, 44, 12, 255))
    img = Image.composite(dark, img, outline)
    img = Image.alpha_composite(img, gold)
    d = ImageDraw.Draw(img)
    # блик
    d.polygon([(52 * s, 100 * s), (60 * s, 96 * s), (60 * s, 186 * s), (52 * s, 190 * s)], fill=(255, 245, 190, 150))
    # камни на ободе
    for x, col in [(76, (214, 40, 40)), (128, (40, 110, 220)), (180, (214, 40, 40))]:
        d.ellipse([(x - 10) * s, 184 * s, (x + 10) * s, 206 * s], fill=(70, 40, 10, 255))
        d.ellipse([(x - 8) * s, 186 * s, (x + 8) * s, 204 * s], fill=col + (255,))
        d.ellipse([(x - 5) * s, 188 * s, (x - 1) * s, 193 * s], fill=(255, 255, 255, 180))
    save(img, "crown.png", (256, 256))


def plank() -> None:
    rnd = random.Random(7)
    w, h = 512 * SS, 128 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rad = 10 * SS
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=rad, fill=(150, 98, 54, 255))
    # волокна: волнистые линии разной яркости
    for i in range(160):
        y0 = rnd.uniform(0, h)
        amp = rnd.uniform(1, 5) * SS
        freq = rnd.uniform(0.002, 0.006) / SS
        ph = rnd.uniform(0, math.tau)
        k = rnd.uniform(-0.18, 0.14)
        col = (int(150 * (1 + k)), int(98 * (1 + k * 1.1)), int(54 * (1 + k * 1.2)), 255)
        pts = [(x, y0 + amp * math.sin(freq * x + ph)) for x in range(0, w, 8 * SS)]
        d.line(pts, fill=col, width=int(rnd.uniform(1, 3) * SS))
    # сучок
    for cx, cy in [(w * 0.71, h * 0.42)]:
        for r in range(int(14 * SS), 0, -int(2 * SS)):
            k = 0.85 + 0.1 * math.sin(r)
            d.ellipse([cx - r * 1.4, cy - r, cx + r * 1.4, cy + r], outline=(int(120 * k), int(74 * k), int(38 * k), 255), width=SS)
    # тень снизу и блик сверху
    for i in range(12 * SS):
        a = int(90 * (1 - i / (12 * SS)))
        d.line([(rad, h - 1 - i), (w - rad, h - 1 - i)], fill=(30, 15, 5, a))
        d.line([(rad, i), (w - rad, i)], fill=(255, 230, 190, a // 3))
    # тёмная рамка
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=rad, outline=(66, 38, 16, 255), width=5 * SS)
    # гвозди
    for x in (26, w / SS - 26):
        for y in (26, 128 - 26):
            cx, cy = x * SS, y * SS
            d.ellipse([cx - 5 * SS, cy - 5 * SS, cx + 5 * SS, cy + 5 * SS], fill=(52, 44, 40, 255))
            d.ellipse([cx - 3 * SS, cy - 3 * SS, cx + 1 * SS, cy + 1 * SS], fill=(150, 140, 130, 255))
    save(img, "plank.png", (512, 128))


def brush_band() -> None:
    rnd = random.Random(3)
    w, h = 1024 * SS, 192 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top, bot = h * 0.22, h * 0.78
    pts_top = []
    pts_bot = []
    for i in range(0, w + 1, 6 * SS):
        t = i / w
        edge = 1.0 - max(0.0, (abs(t - 0.5) - 0.36) / 0.14)  # сходит на нет к концам
        edge = max(0.0, min(1.0, edge))
        thick = (bot - top) * (0.55 + 0.45 * edge)
        mid = h / 2 + 4 * SS * math.sin(t * 9)
        jt = rnd.uniform(-6, 6) * SS
        jb = rnd.uniform(-6, 6) * SS
        pts_top.append((i, mid - thick / 2 + jt))
        pts_bot.append((i, mid + thick / 2 + jb))
    d.polygon(pts_top + pts_bot[::-1], fill=(0, 0, 0, 255))
    # сухие штрихи по краям
    for _ in range(90):
        x0 = rnd.uniform(0, w)
        y0 = rnd.uniform(top - 12 * SS, bot + 12 * SS)
        ln = rnd.uniform(20, 120) * SS
        d.line([(x0, y0), (x0 + ln, y0 + rnd.uniform(-3, 3) * SS)], fill=(0, 0, 0, rnd.randint(90, 220)), width=int(rnd.uniform(1, 4) * SS))
    save(img, "brush_band.png", (1024, 192))


if __name__ == "__main__":
    splatter()
    crown()
    plank()
    brush_band()
