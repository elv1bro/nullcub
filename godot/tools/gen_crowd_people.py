#!/usr/bin/env python3
"""Зрители купола — очертания людей (06.10, автор: «на арене есть куклы на трибунах, надо заменить на какие-то очертания людей +
можешь разного цвета, без деталей»; мир людей — LORE_V2 §2а). Плоские силуэты без лиц и складок: голова, туловище, руки, ноги;
разные фигуры (рост, плечи, дети, платья и пальто, причёски, кепки, капюшоны). Цвет — у каждого зрителя свой: атлас белый
(серым чуть темнее только ноги — брюки), цвет экземпляра MultiMesh умножается в assets/shaders/crowd_sprite.gdshader, палитру
ставит tools/build_null_hall.gd.

Формат — тот же, что у прежнего атласа кукол (tools/blender/crowd_sprites.py): VARIANTS фигур × POSES поз (руки вниз / в стороны /
вверх) в сетке COLS × ROWS, ячейки варианта подряд, ячейка CELL_W × CELL_H м, низ ячейки — пол (ступни).

Запуск: python3 godot/tools/gen_crowd_people.py  → godot/assets/textures/crowd/crowd_atlas.png + crowd_atlas.json
(потом godot --headless --path godot --import; сцену купола пересобрать: godot --headless --path godot -s res://tools/build_null_hall.gd)
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "assets", "textures", "crowd")
OUT_PNG = os.path.join(OUT_DIR, "crowd_atlas.png")
OUT_JSON = os.path.join(OUT_DIR, "crowd_atlas.json")

VARIANTS = 16
POSES = 3
COLS = 8
ROWS = 6
CELL_W = 1.6
CELL_H = 2.25
PX_PER_M = 120
SS = 4                       # суперсэмплинг (сглаженный край)
SEED = 2026
LEGS_SHADE = 196             # ноги чуть темнее (брюки) — 0..255 от белого
HEAD_SHADE = 236

# фигура: рост (м), плечи, бёдра, голова (радиус), толщина руки и ноги, низ (pants | dress | coat), голова (hair | long | pony |
# bun | cap | beanie | hood), масса (худой 0.9 … плотный 1.25)
FIGURES = [
    dict(h=1.80, sh=0.46, hip=0.34, head=0.112, arm=0.085, leg=0.13, low="pants", top="hair", mass=1.0),
    dict(h=1.66, sh=0.40, hip=0.38, head=0.106, arm=0.075, leg=0.12, low="dress", top="long", mass=0.95),
    dict(h=1.74, sh=0.44, hip=0.35, head=0.11, arm=0.085, leg=0.13, low="pants", top="cap", mass=1.05),
    dict(h=1.30, sh=0.32, hip=0.27, head=0.1, arm=0.065, leg=0.1, low="pants", top="hair", mass=0.95),       # ребёнок
    dict(h=1.86, sh=0.52, hip=0.42, head=0.118, arm=0.1, leg=0.15, low="pants", top="beanie", mass=1.25),
    dict(h=1.62, sh=0.39, hip=0.37, head=0.105, arm=0.074, leg=0.12, low="pants", top="pony", mass=0.95),
    dict(h=1.70, sh=0.43, hip=0.40, head=0.108, arm=0.08, leg=0.13, low="coat", top="hood", mass=1.05),
    dict(h=1.78, sh=0.45, hip=0.34, head=0.11, arm=0.082, leg=0.125, low="pants", top="hair", mass=0.9),
    dict(h=1.58, sh=0.38, hip=0.39, head=0.104, arm=0.072, leg=0.12, low="dress", top="bun", mass=1.0),
    dict(h=1.22, sh=0.3, hip=0.26, head=0.098, arm=0.062, leg=0.095, low="dress", top="pony", mass=0.95),     # девочка
    dict(h=1.83, sh=0.48, hip=0.38, head=0.115, arm=0.09, leg=0.14, low="coat", top="cap", mass=1.1),
    dict(h=1.68, sh=0.42, hip=0.36, head=0.108, arm=0.08, leg=0.125, low="pants", top="long", mass=1.0),
    dict(h=1.76, sh=0.47, hip=0.40, head=0.112, arm=0.09, leg=0.14, low="pants", top="hair", mass=1.2),
    dict(h=1.64, sh=0.40, hip=0.38, head=0.106, arm=0.075, leg=0.12, low="coat", top="beanie", mass=1.0),
    dict(h=1.72, sh=0.44, hip=0.35, head=0.11, arm=0.082, leg=0.13, low="pants", top="hood", mass=1.0),
    dict(h=1.60, sh=0.39, hip=0.36, head=0.105, arm=0.074, leg=0.12, low="pants", top="bun", mass=0.95),
]
# позы: угол плеча от «вниз» (градусы, в стороны), угол локтя (доп. сгиб вверх)
POSE_ARMS = [(12.0, 6.0), (95.0, 55.0), (158.0, 12.0)]


def px(v):
    return int(round(v * PX_PER_M * SS))


def capsule(d, a, b, r, fill):
    """Отрезок a–b толщиной 2r со скруглёнными концами."""
    ax, ay = a
    bx, by = b
    d.line([a, b], fill=fill, width=int(2 * r))
    for x, y in (a, b):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def figure(img, d, fig, pose, cx, floor, rng):
    """Рисует фигуру: cx — середина ячейки, floor — пол (y пикселей, вниз растёт)."""
    h = fig["h"]
    m = fig["mass"]
    head_r = px(fig["head"])
    leg_w = px(fig["leg"]) * m
    arm_r = px(fig["arm"]) * 0.5 * m
    sh = px(fig["sh"]) * m
    hip = px(fig["hip"]) * m
    y_head = floor - px(h) + head_r                 # центр головы
    y_neck = y_head + head_r * 0.95
    y_sh = y_neck + px(0.05)
    y_hip = floor - px(h * 0.49)
    y_knee = floor - px(h * 0.27)
    white = 255
    # ноги (брюки — чуть темнее; у платья видны ниже подола)
    for s in (-1, 1):
        x_top = cx + s * (hip * 0.5 - leg_w * 0.5)
        x_bot = cx + s * (hip * 0.5 - leg_w * 0.35)
        d.polygon([(x_top - leg_w * 0.5, y_hip), (x_top + leg_w * 0.5, y_hip), (x_bot + leg_w * 0.42, floor - px(0.06)),
                   (x_bot - leg_w * 0.42, floor - px(0.06))], fill=LEGS_SHADE)
        d.ellipse([x_bot - leg_w * 0.55 + s * px(0.02), floor - px(0.09), x_bot + leg_w * 0.55 + s * px(0.02), floor], fill=LEGS_SHADE)
    # туловище
    waist = (sh + hip) * 0.5 * 0.86
    if fig["low"] == "pants":
        d.polygon([(cx - sh * 0.5, y_sh), (cx + sh * 0.5, y_sh), (cx + waist * 0.5, y_hip + px(0.04)),
                   (cx - waist * 0.5, y_hip + px(0.04))], fill=white)
    else:
        hem = y_knee + (px(0.04) if fig["low"] == "dress" else px(0.1))
        flare = hip * (1.35 if fig["low"] == "dress" else 1.12)
        d.polygon([(cx - sh * 0.5, y_sh), (cx + sh * 0.5, y_sh), (cx + waist * 0.48, y_hip - px(0.12)), (cx + flare * 0.5, hem),
                   (cx - flare * 0.5, hem), (cx - waist * 0.48, y_hip - px(0.12))], fill=white)
    d.ellipse([cx - sh * 0.5 - arm_r, y_sh - arm_r * 0.6, cx - sh * 0.5 + arm_r * 1.6, y_sh + arm_r * 2.2], fill=white)
    d.ellipse([cx + sh * 0.5 - arm_r * 1.6, y_sh - arm_r * 0.6, cx + sh * 0.5 + arm_r, y_sh + arm_r * 2.2], fill=white)
    # шея и голова
    d.rectangle([cx - head_r * 0.42, y_neck - head_r * 0.3, cx + head_r * 0.42, y_sh + px(0.02)], fill=HEAD_SHADE)
    d.ellipse([cx - head_r * 0.92, y_head - head_r, cx + head_r * 0.92, y_head + head_r * 1.02], fill=HEAD_SHADE)
    top = fig["top"]
    if top == "long":
        d.polygon([(cx - head_r * 1.0, y_head - head_r * 0.2), (cx + head_r * 1.0, y_head - head_r * 0.2),
                   (cx + head_r * 1.12, y_sh + px(0.12)), (cx - head_r * 1.12, y_sh + px(0.12))], fill=HEAD_SHADE)
    elif top == "pony":
        capsule(d, (cx + head_r * 0.8, y_head - head_r * 0.2), (cx + head_r * 1.35, y_head + head_r * 1.2), head_r * 0.28, HEAD_SHADE)
    elif top == "bun":
        d.ellipse([cx - head_r * 0.45, y_head - head_r * 1.55, cx + head_r * 0.45, y_head - head_r * 0.7], fill=HEAD_SHADE)
    elif top == "cap":
        d.chord([cx - head_r * 1.0, y_head - head_r * 1.12, cx + head_r * 1.0, y_head + head_r * 0.6], 180, 360, fill=white)
        d.rectangle([cx - head_r * 0.2, y_head - head_r * 0.32, cx + head_r * 1.65, y_head - head_r * 0.14], fill=white)
    elif top == "beanie":
        d.chord([cx - head_r * 1.02, y_head - head_r * 1.3, cx + head_r * 1.02, y_head + head_r * 0.5], 180, 360, fill=white)
        d.ellipse([cx - head_r * 0.25, y_head - head_r * 1.55, cx + head_r * 0.25, y_head - head_r * 1.05], fill=white)
    elif top == "hood":
        d.ellipse([cx - head_r * 1.18, y_head - head_r * 1.2, cx + head_r * 1.18, y_head + head_r * 1.25], fill=white)
    else:   # короткая стрижка — голова чуть шире сверху
        d.chord([cx - head_r * 0.97, y_head - head_r * 1.06, cx + head_r * 0.97, y_head + head_r * 0.4], 180, 360, fill=HEAD_SHADE)
    # руки: плечо → локоть → кисть, у каждого свой небольшой разброс угла
    a_sh, a_el = POSE_ARMS[pose]
    up_len = px(h * 0.19)
    lo_len = px(h * 0.18)
    for s in (-1, 1):
        jit = rng.uniform(-8.0, 8.0)
        a1 = math.radians(a_sh + jit)
        a2 = math.radians(a_sh + jit + a_el)
        sx, sy = cx + s * (sh * 0.5 - arm_r * 0.3), y_sh + arm_r * 0.6
        ex, ey = sx + s * math.sin(a1) * up_len, sy + math.cos(a1) * up_len
        hx, hy = ex + s * math.sin(a2) * lo_len, ey + math.cos(a2) * lo_len
        capsule(d, (sx, sy), (ex, ey), arm_r, white)
        capsule(d, (ex, ey), (hx, hy), arm_r * 0.9, white)
        d.ellipse([hx - arm_r * 1.25, hy - arm_r * 1.25, hx + arm_r * 1.25, hy + arm_r * 1.25], fill=white)


def main():
    rng = random.Random(SEED)
    cw, ch = px(CELL_W), px(CELL_H)
    atlas = Image.new("LA", (cw * COLS, ch * ROWS), (0, 0))
    for v in range(VARIANTS):
        fig = FIGURES[v % len(FIGURES)]
        for p in range(POSES):
            cell = v * POSES + p
            col, row = cell % COLS, cell // COLS
            lum = Image.new("L", (cw, ch), 0)
            alpha = Image.new("L", (cw, ch), 0)
            dl = ImageDraw.Draw(lum)
            da = ImageDraw.Draw(alpha)
            # рисуем дважды: яркость (оттенки ног / головы) и маску (всё — 255)
            figure(lum, dl, fig, p, cw / 2, ch - px(0.01), random.Random(SEED + cell))
            figure(alpha, _Solid(da), fig, p, cw / 2, ch - px(0.01), random.Random(SEED + cell))
            cellimg = Image.merge("LA", (lum, alpha))
            atlas.paste(cellimg, (col * cw, row * ch))
    out = atlas.resize((atlas.width // SS, atlas.height // SS), Image.LANCZOS)
    # жёсткий альфа-край для discard в шейдере: сглаженная маска остаётся, цвет под краем — белый (без тёмной каймы)
    l, a = out.split()
    rgba = Image.merge("RGBA", (l, l, l, a))
    os.makedirs(OUT_DIR, exist_ok=True)
    rgba.save(OUT_PNG)
    meta = {"cols": COLS, "rows": ROWS, "variants": VARIANTS, "poses": POSES, "cell_m": [CELL_W, CELL_H], "px_per_m": PX_PER_M,
            "seed": SEED, "kind": "people", "pose_arms": POSE_ARMS,
            "figures": [{k: f[k] for k in ("h", "low", "top", "mass")} for f in FIGURES[:VARIANTS]]}
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    print("crowd people atlas:", OUT_PNG, rgba.size)


class _Solid:
    """ImageDraw-обёртка для маски: любая заливка — 255."""

    def __init__(self, d):
        self.d = d

    def __getattr__(self, name):
        fn = getattr(self.d, name)

        def call(*args, **kw):
            if "fill" in kw:
                kw["fill"] = 255
            return fn(*args, **kw)
        return call


if __name__ == "__main__":
    main()
