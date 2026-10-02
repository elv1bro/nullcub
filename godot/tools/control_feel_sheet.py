#!/usr/bin/env python3
"""Лист кадров управления: строки — варианты ControlFeel, столбцы — моменты (tests/control_feel_snapshot.gd).
Использование: control_feel_sheet.py <папка с кадрами> <выход.png> <tempo> <air|floor> variant1 variant2 ...
Кадры режутся по центру (кукла в центре) и подписываются."""
import sys
from PIL import Image, ImageDraw

src, out, tempo, mode = sys.argv[1:5]
variants = sys.argv[5:]
CROP = (300, 70, 660, 470)   # из кадра 960x540: область вокруг куклы
cols = 6
cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
sheet = Image.new("RGB", (cols * cw, len(variants) * ch), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for r, v in enumerate(variants):
    for c in range(cols):
        try:
            im = Image.open(f"{src}/{v}_{tempo}_{mode}_{c}.png").convert("RGB").crop(CROP)
        except FileNotFoundError:
            continue
        sheet.paste(im, (c * cw, r * ch))
    d.text((8, r * ch + 6), f"{v} / {tempo} / {mode}", fill=(255, 220, 120))
sheet.save(out)
print("saved", out, sheet.size)
