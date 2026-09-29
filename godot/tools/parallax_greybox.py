#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Грейбокс-листы элементов параллакса в ТОМ ЖЕ формате, что бриф для генерации (docs/plan-demo/PARALLAX.md):
1536×1024, ровный фон #00FF00, объекты не касаются друг друга, подвешенные касаются верхнего края.

Нужны, чтобы проверить весь конвейер (parallax_elements_cut.py → ParallaxScatter3D → снапшот) до прихода арта:
силуэты ферменных башен, кранов, труб (far / mid) и цепей, шестерней, балок, куч хлама (fore). Тёмное тело + тёплая
контровая кайма со всех сторон (контражур — отражение по x не ломает свет, как и требует бриф).

Выход: godot/tests/fixtures/parallax_greybox/{far,mid,fore}_sheet.png
Запуск: /usr/local/bin/python3 godot/tools/parallax_greybox.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "godot", "tests", "fixtures", "parallax_greybox")
W, H = 1536, 1024
SS = 2  # суперсэмплинг
BODY = np.array([0.16, 0.11, 0.09], np.float32)
RIM = np.array([0.85, 0.47, 0.22], np.float32)
LIGHT = np.array([1.0, 0.62, 0.25], np.float32)
BANNER = np.array([0.55, 0.08, 0.07], np.float32)


class Sheet:
    def __init__(self):
        self.mask = Image.new("L", (W * SS, H * SS), 0)
        self.lights = Image.new("L", (W * SS, H * SS), 0)
        self.banner = Image.new("L", (W * SS, H * SS), 0)
        self.d = ImageDraw.Draw(self.mask)
        self.dl = ImageDraw.Draw(self.lights)
        self.db = ImageDraw.Draw(self.banner)

    def line(self, p, q, w):
        self.d.line([(p[0] * SS, p[1] * SS), (q[0] * SS, q[1] * SS)], fill=255, width=max(1, int(w * SS)))

    def poly(self, pts, draw=None):
        (draw or self.d).polygon([(x * SS, y * SS) for x, y in pts], fill=255)

    def rect(self, x0, y0, x1, y1, draw=None):
        (draw or self.d).rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=255)

    def circle(self, cx, cy, r, draw=None, fill=255):
        (draw or self.d).ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=fill)

    def render(self, path):
        m = np.asarray(self.mask, np.float32) / 255.0
        inner = ndimage.grey_erosion(m, size=(3 * SS, 3 * SS))
        rim = np.clip(m - inner, 0.0, 1.0)
        li = np.asarray(self.lights, np.float32)[..., None] / 255.0
        bn = np.asarray(self.banner, np.float32)[..., None] / 255.0
        col = BODY[None, None] * (1 - rim[..., None]) + RIM[None, None] * rim[..., None]
        col = col * (1 - bn) + BANNER * bn
        col = col * (1 - li) + LIGHT * li
        bg = np.array([0.0, 1.0, 0.0], np.float32)
        img = col * m[..., None] + bg * (1 - m[..., None])
        im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").resize((W, H), Image.LANCZOS)
        im.save(path)


def truss_tower(s, x, base, w, h, rng, banner=False, cabin=True):
    top_w = w * rng.uniform(0.55, 0.8)
    lx0, rx0, lx1, rx1 = x - w / 2, x + w / 2, x - top_w / 2, x + top_w / 2
    top = base - h
    s.line((lx0, base), (lx1, top), 7)
    s.line((rx0, base), (rx1, top), 7)
    bays = int(rng.integers(6, 10))
    for i in range(bays + 1):
        t = i / bays
        y = base - h * t
        xl, xr = lx0 + (lx1 - lx0) * t, rx0 + (rx1 - rx0) * t
        s.line((xl, y), (xr, y), 4)
        if i < bays:
            t2 = (i + 1) / bays
            y2 = base - h * t2
            xl2, xr2 = lx0 + (lx1 - lx0) * t2, rx0 + (rx1 - rx0) * t2
            s.line((xl, y), (xr2, y2), 2.5)
            s.line((xr, y), (xl2, y2), 2.5)
            if rng.random() < 0.35:
                s.circle((xl + xr) / 2, (y + y2) / 2, 3, s.dl)
    if cabin:
        cw, ch = top_w * 1.3, h * 0.08
        s.rect(x - cw / 2, top - ch, x + cw / 2, top)
        s.poly([(x - cw / 2 - 6, top - ch), (x, top - ch - h * 0.07), (x + cw / 2 + 6, top - ch)])
        s.line((x, top - ch - h * 0.07), (x, top - ch - h * 0.14), 3)
        for k in range(3):
            s.rect(x - cw / 2 + 8 + k * cw / 3.2, top - ch * 0.7, x - cw / 2 + 16 + k * cw / 3.2, top - ch * 0.35, s.dl)
    if banner:
        bw, bh = w * 0.35, h * 0.18
        by = base - h * 0.55
        s.poly([(x - bw / 2, by), (x + bw / 2, by), (x + bw / 2, by + bh), (x, by + bh * 0.82),
                (x - bw / 2, by + bh)], s.db)
        s.poly([(x - bw / 2, by), (x + bw / 2, by), (x + bw / 2, by + bh), (x, by + bh * 0.82),
                (x - bw / 2, by + bh)])


def crane(s, x, base, w, h, rng):
    truss_tower(s, x, base, w * 0.35, h, rng, cabin=False)
    top = base - h
    jl, jr = x - w * 0.25, x + w * 0.75
    s.line((jl, top), (jr, top), 9)
    s.line((jl, top + 18), (jr * 0.98 + x * 0.02, top + 4), 3)
    s.line((x, top - h * 0.1), (jl, top), 3)
    s.line((x, top - h * 0.1), (jr, top), 3)
    s.rect(jl - 10, top - 4, jl + 26, top + 30)
    hx = x + w * rng.uniform(0.45, 0.7)
    hy = top + h * rng.uniform(0.25, 0.45)
    s.line((hx, top), (hx, hy), 2)
    s.poly([(hx - 26, hy), (hx + 26, hy), (hx + 18, hy + 34), (hx - 18, hy + 34)])


def chimney(s, x, base, w, h, rng):
    s.poly([(x - w / 2, base), (x + w / 2, base), (x + w * 0.32, base - h), (x - w * 0.32, base - h)])
    for k in range(4):
        y = base - h * (0.2 + 0.2 * k)
        ww = w / 2 - (w / 2 - w * 0.32) * (0.2 + 0.2 * k)
        s.rect(x - ww - 5, y - 6, x + ww + 5, y + 6)
    s.rect(x - w * 0.4, base - h - 10, x + w * 0.4, base - h + 6)


def chain(s, x, length, link=34):
    y = 0
    k = 0
    while y < length:
        if k % 2 == 0:
            s.d.ellipse([(x - 13) * SS, y * SS, (x + 13) * SS, (y + link) * SS], outline=255, width=7 * SS)
        else:
            s.rect(x - 4, y, x + 4, y + link)
        y += link * 0.78
        k += 1
    return y


def gear(s, cx, cy, r, teeth, rng):
    pts = []
    for i in range(teeth * 2):
        ang = math.pi * i / teeth
        rr = r if i % 2 == 0 else r * 0.84
        for da in (-0.5, 0.5):
            a2 = ang + da * math.pi / teeth * 0.9
            pts.append((cx + rr * math.cos(a2), cy + rr * math.sin(a2)))
    s.poly(pts)
    s.circle(cx, cy, r * 0.62, s.d, fill=0)
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(0, 1)
        s.line((cx, cy), (cx + r * 0.66 * math.cos(a), cy + r * 0.66 * math.sin(a)), 12)
    s.circle(cx, cy, r * 0.16)


def junk_pile(s, x, base, w, h, rng):
    pts = [(x - w / 2, base)]
    n = 14
    for i in range(1, n):
        t = i / n
        env = math.sin(math.pi * t) ** 0.8
        pts.append((x - w / 2 + w * t, base - h * env * rng.uniform(0.6, 1.0)))
    pts.append((x + w / 2, base))
    s.poly(pts)
    for _ in range(5):
        a = rng.uniform(-1.2, 1.2)
        px = x + rng.uniform(-w * 0.3, w * 0.3)
        py = base - h * rng.uniform(0.3, 0.7)
        L = rng.uniform(60, 140)
        s.line((px, py), (px + L * math.sin(a), py - L * math.cos(a)), rng.uniform(8, 16))


def far_sheet(rng):
    s = Sheet()
    xs = [120, 360, 610, 860, 1120, 1390]
    for i, x in enumerate(xs):
        w = rng.uniform(120, 170)
        h = rng.uniform(560, 760)
        truss_tower(s, x, 1000, w, h, rng, banner=(i % 3 == 1))
    return s


def mid_sheet(rng):
    s = Sheet()
    truss_tower(s, 190, 1000, 230, 760, rng, banner=True)
    crane(s, 520, 1000, 420, 820, rng)
    chimney(s, 1010, 1000, 170, 900, rng)
    truss_tower(s, 1320, 1000, 260, 600, rng, banner=True)
    return s


def fore_sheet(rng):
    s = Sheet()
    chain(s, 90, 640)
    end = chain(s, 230, 480)
    s.poly([(230 - 30, end), (230 + 30, end), (230 + 8, end + 70), (230 - 8, end + 70)])
    gear(s, 500, 770, 200, 14, rng)
    gear(s, 900, 830, 140, 11, rng)
    s.poly([(1010, 1000), (1060, 1000), (1260, 420), (1215, 405)])  # наклонная балка
    junk_pile(s, 1360, 1000, 300, 260, rng)
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(12)
    for name, fn in (("far", far_sheet), ("mid", mid_sheet), ("fore", fore_sheet)):
        path = os.path.join(OUT, name + "_sheet.png")
        fn(rng).render(path)
        print(path)


if __name__ == "__main__":
    main()
