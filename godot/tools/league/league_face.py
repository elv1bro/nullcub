"""Лицо бойца лиги за визором (docs/plan-demo/ART_NULL.md, «Детали лиги v2»): тёмное стекло с одним глазом-щелью — мотив «ока»
Ŋmoalü с листов автора. Им заменяется фото / карточка на FacePlate у бойцов лиги (в кадре Blender — league_fighters.py,
в игре — scripts/league/league_look.gd). Игроку, который поставил голову лиги трофеем, остаётся его фото.
Запуск: python3 godot/tools/league/league_face.py  →  godot/assets/textures/league/league_face.png (256×256, sRGB)."""
import math
import os

import numpy as np
from PIL import Image

N = 256
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "textures", "league", "league_face.png")


def main():
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    u = (x + 0.5) / N * 2.0 - 1.0          # −1…1, вправо
    v = 1.0 - (y + 0.5) / N * 2.0          # −1…1, вверх
    r = np.sqrt(u * u + v * v)
    # стекло: почти чёрное с фиолетовым отсветом к центру и слабыми горизонтальными линиями развёртки
    g = np.exp(-r * r * 2.2)
    base = np.stack([0.008 + 0.02 * g, 0.003 + 0.004 * g, 0.016 + 0.045 * g], -1)
    scan = 1.0 - 0.18 * (np.sin(v * N * math.pi / 3.0) > 0.6)
    img = base * scan[..., None]
    # глаз: миндаль (две дуги), внутри — радужка-кольцо и вертикальный зрачок-щель, всё светится
    ax, ay = 0.72, 0.36
    almond = (np.abs(u) / ax) ** 2 + (np.abs(v) / (ay * np.clip(1.0 - (u / ax) ** 2, 0.0, 1.0) ** 0.5 + 1e-3)) ** 2
    inside = almond < 1.0
    rim = np.exp(-((almond - 1.0) / 0.12) ** 2)
    violet = np.array([0.62, 0.2, 1.0])
    cyan = np.array([0.3, 0.9, 1.0])
    iris_d = np.abs(r - 0.26)
    iris = np.exp(-(iris_d / 0.05) ** 2) * inside
    fill = inside * (0.3 + 0.4 * np.exp(-r * r * 6.0))
    img = img * (1.0 - fill[..., None]) + violet * fill[..., None] * 0.3
    img = img + violet * rim[..., None] * 0.9 + cyan * iris[..., None] * 0.8
    slit = (np.abs(u) < 0.045 * np.clip(1.0 - (v / 0.34) ** 2, 0.0, 1.0) ** 0.5 + 0.004) & (np.abs(v) < 0.34)
    img[slit] = np.array([1.0, 0.92, 1.0])
    # три точки-сенсора над глазом (как на листах: гроздь мелких глаз)
    for cx, cy, rr in ((-0.42, 0.56, 0.05), (0.0, 0.66, 0.06), (0.42, 0.56, 0.05)):
        d = np.sqrt((u - cx) ** 2 + (v - cy) ** 2)
        img = img + cyan * np.exp(-(d / rr) ** 2)[..., None] * 0.9
    img = np.clip(img, 0.0, 1.0)
    srgb = np.where(img <= 0.0031308, img * 12.92, 1.055 * np.power(img, 1 / 2.4) - 0.055)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray((srgb * 255.0 + 0.5).astype(np.uint8), "RGB").save(os.path.abspath(OUT))
    print("league_face →", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
