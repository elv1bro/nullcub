#!/usr/bin/env python3
"""Процедурные текстуры трещин для «сокрушительного удара» (docs/plan-demo/HIT_FX.md §3.2).

Пишет в godot/assets/textures/fx/:
  crack_decal_{0,1,2}.png  512² RGBA — трещины дерева для Decal по стадиям 120/250/400 мс: главная трещина вдоль волокна
                           (ось X текстуры), звезда сколов от точки удара, на стадии 2 — вторая продольная трещина и сколы.
                           Тёмная щель + светлая кромка свежего дерева; альфа — маска.
  crack_glow_{0,1,2}.png   512² RGB — те же щели белым с мягким ореолом: texture_emission Decal («трещины раскалены»).
  crack_screen.png         1024² RGB — экранные трещины «стекла»: R — маска линии (сглаженная), G — путь от центра по трещине
                           (0 … 1, раскрытие: шейдер показывает G < progress), B — номер осколка (сектор между лучами) × 20.
Без внешних ассетов, seed 29 — повторный запуск даёт те же файлы.
Запуск: python3 godot/tools/fx/gen_crack_textures.py  (Pillow + numpy)
"""
from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SEED = 29
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "fx")

DECAL = 512
SS = 2                     # суперсэмплинг рисования
SCREEN = 1024

GAP = (22, 12, 6)          # щель
RAW = (246, 222, 170)      # кромка свежего дерева


def jagged(rng: random.Random, x: float, y: float, ang: float, length: float, step: float, wobble: float,
           grain_pull: float = 0.0) -> list[tuple[float, float]]:
    """Ломаная от (x, y) под углом ang: шаг step, случайный излом wobble рад; grain_pull тянет угол к оси X (волокно)."""
    pts = [(x, y)]
    travelled = 0.0
    a = ang
    while travelled < length:
        a += rng.uniform(-wobble, wobble)
        if grain_pull > 0.0:
            target = 0.0 if math.cos(a) >= 0.0 else math.pi
            d = math.atan2(math.sin(target - a), math.cos(target - a))
            a += d * grain_pull
        s = step * rng.uniform(0.6, 1.3)
        x += math.cos(a) * s
        y += math.sin(a) * s
        travelled += s
        pts.append((x, y))
    return pts


def draw_crack(d_gap: ImageDraw.ImageDraw, d_raw: ImageDraw.ImageDraw, d_glow: ImageDraw.ImageDraw,
               pts: list[tuple[float, float]], w0: float, w1: float) -> None:
    """Щель с сужением w0 → w1 (px в масштабе SS), кромка — сдвинутая светлая линия под щелью."""
    n = len(pts) - 1
    for i in range(n):
        t = i / max(n, 1)
        w = max(w0 + (w1 - w0) * t, 1.0)
        a, b = pts[i], pts[i + 1]
        d_raw.line([(a[0] - w * 0.45, a[1] - w * 0.55), (b[0] - w * 0.45, b[1] - w * 0.55)], fill=255, width=int(round(w + 2 * SS)))
        d_gap.line([a, b], fill=255, width=int(round(w)))
        d_glow.line([a, b], fill=255, width=int(round(w * 0.8 + SS)))


def decal_cracks() -> list[tuple[int, list[tuple[float, float]], float, float]]:
    """Все трещины стадии 2: (стадия появления, ломаная в px×SS, ширина у начала, у конца). Стадии растут из одних трещин."""
    rng = random.Random(SEED * 10 + 7)
    c = DECAL * SS / 2.0
    out: list[tuple[int, list[tuple[float, float]], float, float]] = []
    # главная трещина вдоль волокна (±X)
    for side in (0.0, math.pi):
        pts = jagged(rng, c, c, side + rng.uniform(-0.15, 0.15), 235 * SS, 7 * SS, 0.35, grain_pull=0.28)
        out.append((0, pts, 11 * SS, 1.2 * SS))
    # звезда сколов от точки удара: 5 с нулевой стадии, ещё 2 и 2 позже; ветки — со стадии 1
    for i in range(9):
        a = (i + rng.uniform(-0.3, 0.3)) / 9 * math.tau
        ln = 96 * rng.uniform(0.6, 1.15) * SS
        pts = jagged(rng, c, c, a, ln, 5 * SS, 0.5, grain_pull=0.12)
        out.append((0 if i % 2 == 0 or i == 1 else (1 if i in (3, 5) else 2), pts, 6.5 * SS, 1.0 * SS))
        if rng.random() < 0.7:
            k = min(rng.randrange(1, max(len(pts) - 1, 2)), len(pts) - 1)
            bx, by = pts[k]
            sub = jagged(rng, bx, by, a + rng.choice([-1, 1]) * rng.uniform(0.4, 0.9), ln * 0.45, 4 * SS, 0.5)
            out.append((1, sub, 3.0 * SS, 1.0 * SS))
    # вторая продольная трещина (дерево расщепляется) — стадия 2
    for off in (-1, 1):
        y0 = c + off * rng.uniform(22, 32) * SS
        x0 = c + rng.uniform(-30, 30) * SS
        for side in (0.0, math.pi):
            pts = jagged(rng, x0, y0, side, rng.uniform(90, 150) * SS, 8 * SS, 0.25, grain_pull=0.35)
            out.append((2, pts, 5 * SS, 1.0 * SS))
    return out


def decal_chips() -> list[list[tuple[float, float]]]:
    rng = random.Random(SEED * 10 + 11)
    c = DECAL * SS / 2.0
    chips = []
    for _ in range(7):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(10, 40) * SS
        cx, cy = c + math.cos(a) * r, c + math.sin(a) * r
        chips.append([(cx + math.cos(a + k * 2.1 + rng.uniform(-0.4, 0.4)) * rng.uniform(5, 12) * SS * (2.2 if k % 2 == 0 else 1.0),
                       cy + math.sin(a + k * 2.1 + rng.uniform(-0.4, 0.4)) * rng.uniform(4, 8) * SS) for k in range(3)])
    return chips


def decal_stage(stage: int) -> tuple[Image.Image, Image.Image]:
    size = DECAL * SS
    gap = Image.new("L", (size, size), 0)
    raw = Image.new("L", (size, size), 0)
    glow = Image.new("L", (size, size), 0)
    dg, dr, dl = ImageDraw.Draw(gap), ImageDraw.Draw(raw), ImageDraw.Draw(glow)
    reach = [0.42, 0.72, 1.0][stage]
    for born, pts, w0, w1 in decal_cracks():
        if born > stage:
            continue
        frac = reach if born == 0 else (reach if born < stage else [0.0, 0.6, 0.75][stage])
        n = max(int(round((len(pts) - 1) * frac)), 1)
        widen = [0.7, 0.85, 1.0][stage]
        draw_crack(dg, dr, dl, pts[: n + 1], w0 * widen, w1)
    if stage == 2:
        for poly in decal_chips():
            dr.polygon([(x - 2 * SS, y - 2 * SS) for x, y in poly], fill=255)
            dg.polygon(poly, fill=255)
            dl.polygon(poly, fill=200)
    small = (DECAL, DECAL)
    gap_a = np.asarray(gap.resize(small, Image.LANCZOS), dtype=np.float32) / 255.0
    raw_a = np.asarray(raw.resize(small, Image.LANCZOS), dtype=np.float32) / 255.0
    rgb = np.zeros((DECAL, DECAL, 3), dtype=np.float32)
    rim = np.clip(raw_a - gap_a, 0.0, 1.0)
    alpha = np.clip(gap_a + rim * 0.85, 0.0, 1.0)
    w_gap = gap_a / np.maximum(alpha, 1e-4)
    for ch in range(3):
        rgb[..., ch] = GAP[ch] * w_gap + RAW[ch] * (1.0 - w_gap)
    # мягкое затухание к краям квадрата Decal
    yy, xx = np.mgrid[0:DECAL, 0:DECAL]
    rr = np.hypot(xx - DECAL / 2, yy - DECAL / 2) / (DECAL / 2)
    alpha *= np.clip((1.0 - rr) / 0.12, 0.0, 1.0)
    rgba = np.dstack([rgb, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    glow_small = glow.resize(small, Image.LANCZOS)
    halo = glow_small.filter(ImageFilter.GaussianBlur(5))
    g = np.clip(np.asarray(glow_small, dtype=np.float32) + np.asarray(halo, dtype=np.float32) * 0.9, 0, 255)
    g *= np.clip((1.0 - rr) / 0.12, 0.0, 1.0)
    glow_rgb = np.dstack([g, g, g]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA"), Image.fromarray(glow_rgb, "RGB")


def screen_crack() -> Image.Image:
    rng = random.Random(SEED)
    size = SCREEN
    c = size / 2.0
    mask = Image.new("L", (size * SS, size * SS), 0)
    dm = ImageDraw.Draw(mask)
    dist = np.full((size, size), 255, dtype=np.uint8)
    dist_img = Image.fromarray(dist, "L")
    dd = ImageDraw.Draw(dist_img)
    segs: list[tuple[float, tuple[float, float], tuple[float, float], float]] = []   # (путь, a, b, ширина)
    max_r = size * 0.49
    n_rays = 11
    ray_angles = sorted(((i + rng.uniform(-0.28, 0.28)) / n_rays * math.tau) % math.tau for i in range(n_rays))
    rays: list[list[tuple[float, float, float]]] = []   # точки (x, y, путь)
    for a in ray_angles:
        ln = max_r * rng.uniform(0.65, 1.0)
        pts = jagged(rng, c, c, a, ln, 14, 0.18)
        acc = 0.0
        ray = [(pts[0][0], pts[0][1], 0.0)]
        for i in range(len(pts) - 1):
            p, q = pts[i], pts[i + 1]
            w = 5.0 - 3.2 * (i / max(len(pts) - 1, 1))
            segs.append((acc, p, q, w))
            acc += math.dist(p, q)
            ray.append((q[0], q[1], acc))
        rays.append(ray)
        # ветки
        for _ in range(rng.randint(1, 3)):
            k = rng.randrange(2, max(len(ray) - 2, 3))
            k = min(k, len(ray) - 1)
            bx, by, bd = ray[k]
            sub = jagged(rng, bx, by, a + rng.choice([-1, 1]) * rng.uniform(0.35, 0.8), ln * rng.uniform(0.15, 0.35), 10, 0.25)
            sacc = bd
            for i in range(len(sub) - 1):
                segs.append((sacc, sub[i], sub[i + 1], 2.2))
                sacc += math.dist(sub[i], sub[i + 1])
    # кольцевые дуги паутины между соседними лучами
    for radius in (70.0, 150.0, 260.0, 380.0):
        for i in range(n_rays):
            if rng.random() > [0.95, 0.8, 0.55, 0.35][[70.0, 150.0, 260.0, 380.0].index(radius)]:
                continue
            ra, rb = rays[i], rays[(i + 1) % n_rays]

            def at(ray: list[tuple[float, float, float]], r: float) -> tuple[float, float, float] | None:
                for x, y, dpath in ray:
                    if math.hypot(x - c, y - c) >= r:
                        return (x, y, dpath)
                return None
            pa, pb = at(ra, radius * rng.uniform(0.9, 1.1)), at(rb, radius * rng.uniform(0.9, 1.1))
            if pa is None or pb is None:
                continue
            steps = 6
            prev = (pa[0], pa[1])
            acc = pa[2]
            for s in range(1, steps + 1):
                t = s / steps
                x = pa[0] + (pb[0] - pa[0]) * t
                y = pa[1] + (pb[1] - pa[1]) * t
                # чуть выгнуть наружу и надломить
                bow = math.sin(t * math.pi) * radius * 0.08
                ang = math.atan2(y - c, x - c)
                x += math.cos(ang) * bow + rng.uniform(-3, 3)
                y += math.sin(ang) * bow + rng.uniform(-3, 3)
                segs.append((acc, prev, (x, y), 2.0))
                acc += math.dist(prev, (x, y))
                prev = (x, y)
    max_path = max(s[0] for s in segs) + 1.0
    # G: дальние сначала, ближние поверх (минимум пути)
    for acc, p, q, w in sorted(segs, key=lambda s: -s[0]):
        g = int(round(min(acc / max_path, 1.0) * 254))
        dd.line([p, q], fill=g, width=int(round(w + 4)))
    for acc, p, q, w in segs:
        dm.line([(p[0] * SS, p[1] * SS), (q[0] * SS, q[1] * SS)], fill=255, width=max(int(round(w * SS)), 1))
    m = np.asarray(mask.resize((size, size), Image.LANCZOS), dtype=np.uint8)
    g = np.asarray(dist_img, dtype=np.uint8)
    # B: осколок — сектор между лучами
    yy, xx = np.mgrid[0:size, 0:size]
    ang = (np.arctan2(yy - c, xx - c)) % math.tau
    sector = np.zeros((size, size), dtype=np.uint8)
    for i, a in enumerate(ray_angles):
        sector[ang >= a] = (i + 1) % n_rays
    b = (sector.astype(np.int32) * 20).clip(0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([m, g, b]), "RGB")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for s in range(3):
        albedo, glow = decal_stage(s)
        albedo.save(os.path.join(OUT, f"crack_decal_{s}.png"), optimize=True)
        glow.save(os.path.join(OUT, f"crack_glow_{s}.png"), optimize=True)
    screen_crack().save(os.path.join(OUT, "crack_screen.png"), optimize=True)
    for f in sorted(os.listdir(OUT)):
        if f.startswith("crack_") and f.endswith(".png"):
            print(f, os.path.getsize(os.path.join(OUT, f)))


if __name__ == "__main__":
    main()
