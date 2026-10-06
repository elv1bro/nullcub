#!/usr/bin/env python3
"""Схема карты «Гонка: трасса» (docs/plan-demo/RACE_TRACK.md) из JSON пробы:
  godot --headless --path godot --fixed-fps 60 res://tests/track_probe.tscn -- "only=dump,dump=/abs/track.json"
  python3 godot/tools/race_track_map.py /abs/track.json docs/plan-demo/img/track/map.png
Три полосы по ~150 м (x вдоль трассы, y вверх): твёрдое — тёмное, небо над открытыми залами — светлое, линия ботов (главная — белая,
лёгкая ветка — зелёная, трудная — оранжевая), контрольные точки (голубые ворота с номером), поля гравитации (рамка, стрелка, сила в G),
сетки KO — красные, прессы, магниты, мосты, бочки, кольца, метки порталов (фиолетовые, со стрелкой нормали), финиш.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

SCALE = 8.0
ROWS = [(-12.0, 138.0), (134.0, 284.0), (280.0, 430.0)]
Y0, Y1 = -20.0, 24.0
SKY = [(-16.0, 16.0, 74.0, 32.0), (200.0, 16.0, 288.0, 32.0), (342.0, 14.0, 430.0, 32.0)]
MARGIN = 26
ROW_GAP = 34


def main() -> None:
    data = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    row_w = int((ROWS[0][1] - ROWS[0][0]) * SCALE)
    row_h = int((Y1 - Y0) * SCALE)
    img = Image.new("RGB", (row_w + MARGIN * 2, (row_h + ROW_GAP) * len(ROWS) + MARGIN), (236, 232, 222))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
        small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    except OSError:
        font = small = ImageFont.load_default()
    for ri, (x0, x1) in enumerate(ROWS):
        oy = MARGIN + ri * (row_h + ROW_GAP)

        def pt(x: float, y: float) -> tuple:
            return (MARGIN + (x - x0) * SCALE, oy + (Y1 - y) * SCALE)

        def rect(x: float, y: float, w: float, h: float, fill=None, outline=None, width=1) -> None:
            a = pt(max(x, x0), min(y + h, Y1))
            b = pt(min(x + w, x1), max(y, Y0))
            if b[0] <= a[0] or b[1] <= a[1]:
                return
            d.rectangle([a, b], fill=fill, outline=outline, width=width)

        rect(x0, Y0, x1 - x0, Y1 - Y0, fill=(250, 248, 242))
        for z in data["zones"]:
            heavy = z[5] < -0.5 and z[6] > 0.5
            rect(z[0], z[1], z[2], z[3], fill=(250, 214, 205) if heavy else (214, 226, 250))
        for s in data["solid"]:
            rect(s[0], s[1], s[2], s[3], fill=(78, 70, 68))
        for sx0, sy0, sx1, sy1 in SKY:
            for s in data["solid"]:
                ix0, iy0 = max(s[0], sx0), max(s[1], sy0)
                ix1, iy1 = min(s[0] + s[2], sx1), min(s[1] + s[3], sy1)
                if ix1 > ix0 and iy1 > iy0:
                    rect(ix0, iy0, ix1 - ix0, iy1 - iy0, fill=(196, 214, 232))
        for z in data["zones"]:
            heavy = z[5] < -0.5 and z[6] > 0.5
            col = (210, 70, 50) if heavy else (60, 100, 210)
            rect(z[0], z[1], z[2], z[3], outline=col, width=2)
            cx, cy = z[0] + z[2] * 0.5, z[1] + min(z[3], 20.0) * 0.5
            if cy > Y1 - 2:
                cy = Y1 - 3
            a = pt(cx, cy)
            b = pt(cx + z[4] * 3.0, cy + z[5] * 3.0)
            d.line([a, b], fill=col, width=4)
            d.ellipse([b[0] - 4, b[1] - 4, b[0] + 4, b[1] + 4], fill=col)
            d.text((a[0] + 8, a[1] - 18), "%.2fG" % z[6], fill=col, font=font)
        for g in data["grids"]:
            rect(g[0], g[1], g[2], g[3], fill=(230, 40, 30) if g[4] == "grid" else (255, 150, 120))
        for x in data["presses"]:
            rect(x - 1.0, 0.12, 2.0, 3.2, outline=(200, 60, 30), width=2)
            rect(x - 1.0, 3.3, 2.0, 0.8, fill=(200, 60, 30))
        for m in data["magnets"]:
            a = pt(m[0], m[1])
            d.ellipse([a[0] - 8, a[1] - 8, a[0] + 8, a[1] + 8], outline=(60, 60, 200), width=3)
            r = pt(m[0] + 6.0, m[1])[0] - a[0]
            d.ellipse([a[0] - r, a[1] - r, a[0] + r, a[1] + r], outline=(120, 120, 220), width=1)
        for x in data["bridges"]:
            d.line([pt(x, 0.1), pt(x + 4.0, 0.1)], fill=(150, 100, 50), width=4)
        for x in data["barrels"]:
            rect(x - 0.3, 0.0, 0.6, 0.9, fill=(200, 40, 40))
        for r in data["rings"]:
            a = pt(r[0], r[1])
            rr = 1.45 * SCALE
            d.ellipse([a[0] - rr, a[1] - rr, a[0] + rr, a[1] + rr], outline=(230, 170, 30), width=3)
        for seg in data["route"]:
            col = {"main": (255, 255, 255), "easy": (40, 170, 70), "hard": (240, 130, 20)}[seg["kind"]]
            pts = [pt(p[0], p[1]) for p in seg["pts"]]
            d.line(pts, fill=(30, 30, 30), width=6)
            d.line(pts, fill=col, width=3)
        for c in data["cps"]:
            if c[2] == 0:
                continue
            d.line([pt(c[0], 0.0), pt(c[0], c[1])], fill=(40, 200, 230), width=3)
            a = pt(c[0], c[1])
            d.text((a[0] + 4, a[1] + 2), "CP%d" % c[2], fill=(20, 120, 160), font=font)
        for p in data["portals"]:
            a = pt(p[0], p[1])
            d.line([pt(p[0], p[1] - 1.3), pt(p[0], p[1] + 1.3)], fill=(150, 40, 200), width=5)
            d.line([a, pt(p[0] + p[2] * 3.0, p[1])], fill=(150, 40, 200), width=3)
            d.text((a[0] - 30, a[1] - 34), p[3].replace("PortalSlot", "Slot "), fill=(150, 40, 200), font=font)
        fx = data["finish_x"]
        for k in range(int(12 / 0.75)):
            rect(fx - 0.4, k * 0.75, 0.8, 0.75, fill=(20, 20, 20) if k % 2 else (255, 255, 255))
        for s in data["sections"]:
            if x0 <= s["x0"] <= x1:
                a = pt(s["x0"], Y1)
                d.line([a, pt(s["x0"], Y0)], fill=(120, 120, 120), width=1)
                d.text((a[0] + 4, a[1] + 2), "%d" % s["index"], fill=(40, 40, 40), font=font)
        for x in range(int(x0 // 10 * 10), int(x1) + 1, 10):
            if x < x0:
                continue
            a = pt(x, Y0)
            d.line([a, (a[0], a[1] + 5)], fill=(60, 60, 60), width=1)
            if x % 50 == 0:
                d.text((a[0] - 10, a[1] + 6), "%d м" % x, fill=(60, 60, 60), font=small)
    img.save(out)
    print("map →", out)


if __name__ == "__main__":
    main()
